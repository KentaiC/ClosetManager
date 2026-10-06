import Foundation
import ClosetCore
import ClosetStorage
import ClosetServices
import Hummingbird

/// 写操作与计算类接口：编辑、删除、穿着与脱下、洗衣、收藏、生成、看板、筛选、差旅、设置。
/// 所有写请求都已经过 `RequestGuardMiddleware` 的来源校验。
struct WriteRoutes: Sendable {
    let store: ClosetStore
    let catalog: CatalogService
    let now: @Sendable () -> Date

    var items: ItemService { ItemService(store: store, now: now) }
    var lifecycle: LifecycleService { LifecycleService(store: store, now: now) }
    var outfits: OutfitService { OutfitService(store: store, now: now) }
    var insights: InsightService { InsightService(store: store, now: now) }
    var settings: SettingsService { SettingsService(store: store, now: now) }

    func register(on api: RouterGroup<BasicRequestContext>) {
        api.put("items/:id", use: updateItem)
        api.delete("items/:id", use: deleteItem)
        api.get("naming/default-name", use: defaultName)

        api.post("wear-records", use: wear)
        api.post("wear-records/:id/take-off", use: takeOff)
        api.delete("wear-records/:id", use: deleteWearRecord)
        api.post("laundry/return", use: returnFromLaundry)

        api.get("outfit-suggestions", use: suggestions)
        api.post("outfits", use: createOutfit)
        api.post("outfits/:id/wear", use: wearOutfit)
        api.delete("outfits/:id", use: deleteOutfit)

        api.get("analytics", use: analytics)
        api.get("search", use: search)

        api.get("travel/plan", use: travelPlan)
        api.post("travel/pack", use: pack)
        api.post("travel/unpack-all", use: unpackAll)

        api.get("settings/profile", use: profile)
        api.put("settings/profile", use: updateProfile)
    }

    // MARK: - 单品

    @Sendable func updateItem(_ request: Request, context: BasicRequestContext) async throws -> APIItem {
        let id = try APIRoutes.uuidParameter(context)
        let body = try await request.decode(as: ItemUpdateBody.self, context: context)
        return APIItem(try await items.update(id: id, with: try body.edit()), now: now())
    }

    @Sendable func deleteItem(_ request: Request, context: BasicRequestContext) async throws -> Response {
        try await items.delete(id: try APIRoutes.uuidParameter(context))
        return Response(status: .noContent)
    }

    /// 「颜色 + 子类」默认名称，供编辑页在名称留空时预览。
    @Sendable func defaultName(_ request: Request, context: BasicRequestContext) async throws -> APIDefaultName {
        let query = request.uri.queryParameters
        let category: ClosetCore.Category = try parse(query.get("category") ?? "", "category")
        let subtype: Subtype? = try parseOptional(query.get("subtype"), "subtype")
        let hex = (query.get("color") ?? "").replacingOccurrences(of: "#", with: "")
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { throw APIError.invalidParameter("color", hex) }
        let color = StoredColor(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
        return APIDefaultName(name: ItemDefaults.defaultName(color: color, subtype: subtype, category: category))
    }

    // MARK: - 穿着与洗衣

    @Sendable func wear(_ request: Request, context: BasicRequestContext) async throws -> APIWearRecord {
        let body = try await request.decode(as: WearBody.self, context: context)
        let record = try await lifecycle.wear(members: try body.members.map { try $0.member() }, outfitID: body.outfitId)
        return APIWearRecord(try await catalog.resolve(record))
    }

    @Sendable func takeOff(_ request: Request, context: BasicRequestContext) async throws -> APIWearRecord {
        let id = try APIRoutes.uuidParameter(context)
        let body = try await request.decode(as: TakeOffBody.self, context: context)
        let record = try await lifecycle.takeOff(recordID: id, laundryItemIDs: Set(body.laundryItemIds))
        return APIWearRecord(try await catalog.resolve(record))
    }

    @Sendable func deleteWearRecord(_ request: Request, context: BasicRequestContext) async throws -> Response {
        try await lifecycle.deleteWearRecord(id: try APIRoutes.uuidParameter(context))
        return Response(status: .noContent)
    }

    @Sendable func returnFromLaundry(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIItem> {
        let body = try await request.decode(as: ItemIDsBody.self, context: context)
        let timestamp = now()
        return APIList(items: try await lifecycle.returnFromLaundry(itemIDs: body.itemIds).map { APIItem($0, now: timestamp) })
    }

    // MARK: - 穿搭

    @Sendable func suggestions(_ request: Request, context: BasicRequestContext) async throws -> APISuggestions {
        let query = request.uri.queryParameters
        let warmth: WarmthLevel = try parse(query.get("warmth") ?? "", "warmth")
        let scenario: Scenario = try parse(query.get("scenario") ?? "", "scenario")
        let waterproof = query.get("requireWaterproof") == "true"
        let maxCount = query.get("maxCount").flatMap(Int.init) ?? 8
        guard (1...20).contains(maxCount) else { throw APIError.invalidParameter("maxCount", "\(maxCount)") }
        var rng = SystemRandomNumberGenerator()
        let result = try await outfits.suggestions(warmth: warmth, scenario: scenario, requireWaterproof: waterproof, maxCount: maxCount, using: &rng)
        let timestamp = now()
        return APISuggestions(
            drafts: result.drafts.map { draft in
                APISuggestion(id: draft.id, members: draft.members.map { APIOutfit.Member(slot: $0.slot.rawValue, item: APIItem($0.item, now: timestamp)) })
            },
            missingRequired: result.missingRequired.map(\.rawValue))
    }

    @Sendable func createOutfit(_ request: Request, context: BasicRequestContext) async throws -> APIOutfit {
        let body = try await request.decode(as: OutfitCreateBody.self, context: context)
        let outfit = try await outfits.create(
            name: body.name, isFavorite: body.isFavorite ?? true, source: try parse(body.source, "source"),
            targetScenario: try parseOptional(body.targetScenario, "targetScenario"),
            targetWarmthLevel: try parseOptional(body.targetWarmthLevel, "targetWarmthLevel"),
            members: try body.members.map { try $0.member() })
        return APIOutfit(try await catalog.resolve(outfit))
    }

    @Sendable func wearOutfit(_ request: Request, context: BasicRequestContext) async throws -> APIWearRecord {
        let record = try await lifecycle.wearOutfit(id: try APIRoutes.uuidParameter(context))
        return APIWearRecord(try await catalog.resolve(record))
    }

    @Sendable func deleteOutfit(_ request: Request, context: BasicRequestContext) async throws -> Response {
        try await outfits.delete(id: try APIRoutes.uuidParameter(context))
        return Response(status: .noContent)
    }

    // MARK: - 看板与筛选

    @Sendable func analytics(_ request: Request, context: BasicRequestContext) async throws -> APIAnalytics {
        let summary = try await insights.analytics()
        let calendar = Calendar.current
        let days = summary.dailyActivity.sorted { $0.key < $1.key }.map { date, count in
            let parts = calendar.dateComponents([.year, .month, .day], from: date)
            return APIAnalytics.DayCount(
                date: String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0), count: count)
        }
        return APIAnalytics(
            inventory: summary.inventory.map { .init(category: $0.category.rawValue, count: $0.count) },
            colorInventory: summary.colorInventory.map { .init(colorCategory: $0.color.rawValue, count: $0.count) },
            colorFrequency: summary.colorFrequency.map { .init(colorCategory: $0.color.rawValue, count: $0.count) },
            dailyActivity: days)
    }

    @Sendable func search(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIItem> {
        let query = request.uri.queryParameters
        let unwornDays = try query.get("unwornDays").map { raw -> Int in
            guard let days = Int(raw), (1...3650).contains(days) else { throw APIError.invalidParameter("unwornDays", raw) }
            return days
        }
        let results = try await insights.search(
            scenario: try parseOptional(query.get("scenario"), "scenario"),
            waterproofOnly: query.get("waterproof") == "true",
            colorCategory: try parseOptional(query.get("colorCategory"), "colorCategory"),
            unwornDays: unwornDays)
        let timestamp = now()
        return APIList(items: results.map { APIItem($0, now: timestamp) })
    }

    // MARK: - 差旅

    @Sendable func travelPlan(_ request: Request, context: BasicRequestContext) async throws -> APITravelPlan {
        let query = request.uri.queryParameters
        guard let days = query.get("days").flatMap(Int.init) else { throw APIError.invalidParameter("days", query.get("days") ?? "") }
        var rng = SystemRandomNumberGenerator()
        let plan = try await insights.travelPlan(
            days: days, warmth: try parse(query.get("warmth") ?? "", "warmth"),
            scenario: try parse(query.get("scenario") ?? "", "scenario"), using: &rng)
        let timestamp = now()
        return APITravelPlan(
            days: plan.days, underwearCount: plan.underwearCount, socksCount: plan.socksCount, showsCapHint: plan.showsCapHint,
            packingCap: TravelService.packingCap, suggestion: plan.suggestion.map { APIItem($0, now: timestamp) },
            missingRequired: plan.missingRequired.map(\.rawValue))
    }

    @Sendable func pack(_ request: Request, context: BasicRequestContext) async throws -> APIList<APIItem> {
        let body = try await request.decode(as: ItemIDsBody.self, context: context)
        let timestamp = now()
        return APIList(items: try await lifecycle.pack(itemIDs: body.itemIds).map { APIItem($0, now: timestamp) })
    }

    @Sendable func unpackAll(_ request: Request, context: BasicRequestContext) async throws -> APICount {
        APICount(count: try await lifecycle.unpackAll())
    }

    // MARK: - 设置

    @Sendable func profile(_ request: Request, context: BasicRequestContext) async throws -> ProfileBody {
        ProfileBody(try await settings.profile())
    }

    @Sendable func updateProfile(_ request: Request, context: BasicRequestContext) async throws -> ProfileBody {
        let body = try await request.decode(as: ProfileBody.self, context: context)
        return ProfileBody(try await settings.updateProfile(body.profile))
    }
}
