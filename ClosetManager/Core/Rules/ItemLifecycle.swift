import Foundation

/// 单品状态流转规则。
///
/// App 的 `WearService` 与本地 Web 服务端都调用这里的函数，脱下与穿着前检查只有一份实现。
public enum ItemLifecycle {
    /// 与流转相关的两个字段。
    public struct State: Equatable, Sendable {
        public var status: ItemStatus
        public var laundryEntryDate: Date?

        public init(status: ItemStatus, laundryEntryDate: Date?) {
            self.status = status
            self.laundryEntryDate = laundryEntryDate
        }
    }

    /// 脱下：只处理当前在衣橱中的单品。勾选的进洗衣袋并记录入袋时间，未勾选的留在衣橱并清空入袋时间。
    ///
    /// 在洗衣袋或行李箱中的单品保持原状态与入袋时间不变。修复审计 H-03：此前未勾选的单品一律被改回衣橱，
    /// 收藏中一件在行李箱或洗衣袋里的单品被穿着再脱下后，状态与入袋时间会被静默改写。
    public static func takeOff(_ current: State, sentToLaundry: Bool, now: Date) -> State {
        guard current.status == .inWardrobe else { return current }
        return sentToLaundry ? State(status: .inLaundry, laundryEntryDate: now) : State(status: .inWardrobe, laundryEntryDate: nil)
    }

    /// 穿着前检查的一件单品。
    public struct WearCandidate: Equatable, Sendable {
        public var title: String
        public var category: Category
        public var status: ItemStatus

        public init(title: String, category: Category, status: ItemStatus) {
            self.title = title
            self.category = category
            self.status = status
        }
    }

    /// 穿着前检查的结果。
    public struct WearCheck: Equatable, Sendable {
        /// 不在衣橱中的单品。
        public var unavailable: [WearCandidate]
        /// 缺少的必选分类。
        public var missingRequired: [Category]

        public var isAllowed: Bool { unavailable.isEmpty && missingRequired.isEmpty }

        /// 给用户的提示；可以穿时为 nil。
        public var message: String? {
            var parts: [String] = []
            if !missingRequired.isEmpty {
                parts.append("这套穿搭缺少：\(missingRequired.map(\.displayName).joined(separator: "、"))。相关单品可能已被删除。")
            }
            if !unavailable.isEmpty {
                let list = unavailable.map { "\($0.title)\($0.status.displayName)" }.joined(separator: "，")
                parts.append("这套穿搭中有单品不在衣橱：\(list)。请先放回衣橱再穿。")
            }
            return parts.isEmpty ? nil : parts.joined(separator: "")
        }
    }

    /// 穿着前检查（修复审计 H-03）：每件单品都必须在衣橱中。
    /// - Parameter requireComplete: 穿已保存的穿搭时还要求上装、下装、鞋子齐全；生成与拼搭的草稿在构造时已保证。
    public static func checkWear(_ items: [WearCandidate], requireComplete: Bool) -> WearCheck {
        let present = Set(items.map(\.category))
        return WearCheck(
            unavailable: items.filter { $0.status != .inWardrobe },
            missingRequired: requireComplete ? Category.allCases.filter { $0.isRequiredInOutfit && !present.contains($0) } : [])
    }

    /// 洗净放回（`WearService.returnToWardrobe`）。
    public static func returnFromLaundry() -> State {
        State(status: .inWardrobe, laundryEntryDate: nil)
    }

    /// 装入行李箱：只改变状态，入袋时间保持原样（`WearService.packIntoLuggage`）。
    public static func pack(_ current: State) -> State {
        State(status: .inLuggage, laundryEntryDate: current.laundryEntryDate)
    }

    /// 结束差旅取出：只改变状态，入袋时间保持原样（`WearService.unpackAllLuggage`）。
    public static func unpack(_ current: State) -> State {
        State(status: .inWardrobe, laundryEntryDate: current.laundryEntryDate)
    }
}
