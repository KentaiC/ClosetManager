import type { ApiItem } from '../../api/types'

export interface GalleryFilter {
  /** 为 undefined 表示「全部」。 */
  category?: string
  showLaundry: boolean
}

/**
 * 衣橱网格中可见的单品，规则与 App 的 WardrobeGalleryView 相同：
 * 在衣橱的单品总是显示，洗衣袋中的单品只在开关打开时显示，行李箱中的单品始终隐藏。
 */
export function visibleGalleryItems(items: readonly ApiItem[], filter: GalleryFilter): ApiItem[] {
  return items
    .filter((item) => item.status === 'inWardrobe' || (item.status === 'inLaundry' && filter.showLaundry))
    .filter((item) => filter.category === undefined || item.category === filter.category)
}
