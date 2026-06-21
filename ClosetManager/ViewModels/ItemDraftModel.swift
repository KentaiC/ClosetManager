import SwiftUI
import PhotosUI

/// 单品录入/编辑的可复用草稿模型（逻辑层，与 UI 解耦）。
///
/// 单件编辑（`ItemEditorView`）与批量录入（`BatchImportView`）共用本模型，
/// 集中持有全部可编辑字段、图像/颜色，以及抠图 + 取色的处理逻辑。
@Observable
final class ItemDraftModel {
    /// 抠图处理状态。
    enum ProcessingState: Equatable {
        case idle
        case processing
        case success
        case failed(String)
    }

    // 名称（自动 / 手动）
    var customName: String = ""
    var nameManuallyEdited: Bool = false

    // 属性
    var category: Category = .top
    var subtype: Subtype?
    var selectedScenarios: Set<Scenario> = []
    /// 保暖度（1~100，叠穿算法用），替代旧的多档标签。
    var warmthScore: Int = 50
    var selectedSeasons: Set<Season> = []
    var seasonsManuallyEdited: Bool = false
    var status: ItemStatus = .inWardrobe
    var isWaterproof: Bool = false
    var brand: String = ""
    var notes: String = ""

    // 图像 / 颜色
    var originalImageData: Data?
    var processedImageData: Data?
    var dominantColor: StoredColor = StoredColor(red: 0.5, green: 0.5, blue: 0.5)
    var secondaryColor: StoredColor?
    var processingState: ProcessingState = .idle

    init() {}

    /// 从既有单品载入（编辑模式）。
    init(editing item: ClothingItem) {
        customName = item.name
        nameManuallyEdited = !item.name.isEmpty
        category = item.category
        subtype = item.subtype
        selectedScenarios = Set(item.scenarios)
        warmthScore = item.warmthScore
        selectedSeasons = Set(item.seasons)
        seasonsManuallyEdited = !item.seasons.isEmpty
        status = item.status
        isWaterproof = item.isWaterproof
        brand = item.brand ?? ""
        notes = item.notes ?? ""
        originalImageData = item.originalImageData
        processedImageData = item.processedImageData
        dominantColor = item.dominantColor
        secondaryColor = item.secondaryColor
    }

    // MARK: - 派生

    /// 当前用于预览的图片：优先去背结果，回退原图。
    var displayImageData: Data? { processedImageData ?? originalImageData }

    /// 自动名称：颜色 + 子类。
    var defaultName: String {
        ClothingItem.defaultName(color: dominantColor, subtype: subtype, category: category)
    }

    /// 最终采用的名称。
    var resolvedName: String { nameManuallyEdited ? customName : defaultName }

    /// 是否允许保存：至少有一张图片且未在处理中。
    var canSave: Bool { displayImageData != nil && processingState != .processing }

    // MARK: - 处理

    /// 处理所选图片：本地抠图 + 取色。
    @MainActor
    func process(_ item: PhotosPickerItem) async {
        processingState = .processing
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                processingState = .failed("无法读取所选图片。")
                return
            }
            originalImageData = data
            let processed = try await VisionService.shared.removeBackground(from: data)
            processedImageData = processed
            await extractColors(from: processed)
            processingState = .success
        } catch {
            processedImageData = nil
            if let original = originalImageData {
                await extractColors(from: original)
            }
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            processingState = .failed(message)
        }
    }

    @MainActor
    private func extractColors(from data: Data) async {
        let colors = await VisionService.shared.extractColors(from: data)
        dominantColor = colors.dominant
        secondaryColor = colors.secondary
    }

    /// 当前保暖度对应的档位（用于季节推导与展示）。
    var warmthLevel: WarmthLevel { WarmthLevel.from(score: warmthScore) }

    /// 保暖度变化时，若季节未手动编辑则自动推导。
    func deriveSeasonsIfNeeded() {
        guard !seasonsManuallyEdited else { return }
        selectedSeasons = Set(Season.derive(from: [warmthLevel]))
    }

    /// 切换分类后，清理不匹配的子类。
    func reconcileSubtype() {
        if let current = subtype, current.category != category {
            subtype = nil
        }
    }

    // MARK: - 落库

    private var scenarioArray: [Scenario] { Scenario.allCases.filter { selectedScenarios.contains($0) } }
    private var warmthArray: [WarmthLevel] { [warmthLevel] }
    private var seasonArray: [Season] { Season.allCases.filter { selectedSeasons.contains($0) } }

    /// 生成新单品（单件新增 / 批量录入）。
    func makeNewItem() -> ClothingItem {
        ClothingItem(
            name: resolvedName,
            category: category,
            subtype: subtype,
            scenarios: scenarioArray,
            status: status,
            isWaterproof: isWaterproof,
            processedImageData: processedImageData,
            originalImageData: originalImageData,
            dominantColor: dominantColor,
            secondaryColor: secondaryColor,
            warmthScore: warmthScore,
            warmthLevels: warmthArray,
            seasons: seasonArray,
            brand: brand.isEmpty ? nil : brand,
            notes: notes.isEmpty ? nil : notes
        )
    }

    /// 应用到既有单品（编辑保存）。
    func apply(to item: ClothingItem) {
        item.name = resolvedName
        item.category = category
        item.subtype = subtype
        item.scenarios = scenarioArray
        item.warmthScore = warmthScore
        item.warmthLevels = warmthArray
        item.seasons = seasonArray
        item.status = status
        item.isWaterproof = isWaterproof
        item.brand = brand.isEmpty ? nil : brand
        item.notes = notes.isEmpty ? nil : notes
        item.originalImageData = originalImageData
        item.processedImageData = processedImageData
        item.dominantColor = dominantColor
        item.secondaryColor = secondaryColor
        item.refreshColorCategory()
        item.updatedAt = .now
    }
}
