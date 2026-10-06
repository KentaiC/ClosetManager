// 与服务端 Server/Sources/ClosetHTTP/APIModels.swift、APIMeta.swift 对应的类型。
// 枚举以原始值字符串传输，中文名称从 /api/v1/meta 读取。

export interface ApiColor {
  red: number
  green: number
  blue: number
  alpha: number
  hex: string
  name: string
}

export interface ApiImage {
  url: string
  format: string
  byteCount: number
  displayable: boolean
}

export interface ApiItem {
  id: string
  name: string
  title: string
  category: string
  subtype: string | null
  scenarios: string[]
  status: string
  isWaterproof: boolean
  laundryEntryDate?: string
  /** 在洗衣袋中超过阈值，由服务端按共享核心规则计算。 */
  laundryRetentionWarning: boolean
  dominantColor: ApiColor
  secondaryColor?: ApiColor
  dominantColorCategory: string
  warmthScore: number
  warmthLevel: string
  warmthLevels: string[]
  seasons: string[]
  brand?: string
  notes?: string
  createdAt: string
  updatedAt: string
  images: {
    display?: ApiImage
    processed?: ApiImage
    original?: ApiImage
  }
}

export interface ApiOutfitMember {
  slot?: string
  item: ApiItem
}

export interface ApiOutfit {
  id: string
  name: string
  isFavorite: boolean
  source: string
  targetScenario?: string
  targetWarmthLevel?: string
  members: ApiOutfitMember[]
  missingRequiredCategories: string[]
  createdAt: string
  updatedAt: string
}

export interface ApiWearRecord {
  id: string
  date: string
  isActive: boolean
  outfitId?: string
  items: ApiItem[]
  notes?: string
  createdAt: string
}

export interface ApiList<T> {
  items: T[]
}

export interface ApiHealth {
  status: string
  version: string
  schemaVersion: number
  counts: { items: number; outfits: number; wearRecords: number; media: number }
  capabilities: { backgroundRemoval: boolean; similarityDetection: boolean }
}

export interface MetaOption {
  value: string
  displayName: string
}

export interface ApiMeta {
  categories: (MetaOption & { isRequiredInOutfit: boolean; washByDefaultOnTakeOff: boolean; subtypes: MetaOption[] })[]
  scenarios: (MetaOption & { conflictsWith: string[] })[]
  statuses: MetaOption[]
  warmthLevels: (MetaOption & {
    representativeScore: number
    minScore: number
    maxScore: number
    torsoBudget: number
    maxSingleGarmentWarmth: number
    seasons: string[]
  })[]
  seasons: MetaOption[]
  colorCategories: MetaOption[]
  outfitSources: MetaOption[]
  genders: MetaOption[]
  rules: { laundryRetentionWarningDays: number; unwornDays: number; travelPackingCap: number }
}

export interface ApiSuggestion {
  id: string
  members: ApiOutfitMember[]
}

export interface ApiSuggestions {
  drafts: ApiSuggestion[]
  missingRequired: string[]
}

export interface ApiAnalytics {
  inventory: { category: string; count: number }[]
  colorInventory: { colorCategory: string; count: number }[]
  colorFrequency: { colorCategory: string; count: number }[]
  dailyActivity: { date: string; count: number }[]
}

export interface ApiTravelPlan {
  days: number
  underwearCount: number
  socksCount: number
  showsCapHint: boolean
  packingCap: number
  suggestion: ApiItem[]
  missingRequired: string[]
}

export interface ApiProfile {
  heightCm: number
  weightKg: number
  age: number
  gender: string
}

export interface ApiMember {
  itemId: string
  slot?: string
}

/** 编辑单品时提交的全部字段，对应服务端 ItemUpdateBody。 */
export interface ItemUpdate {
  name: string
  category: string
  subtype: string | null
  scenarios: string[]
  warmthScore: number
  seasons: string[]
  status: string
  isWaterproof: boolean
  brand: string
  notes: string
  dominantColor: { red: number; green: number; blue: number; alpha: number }
}
