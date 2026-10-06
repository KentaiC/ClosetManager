import type { ApiItem, ApiMember, ApiOutfitMember } from '../../api/types'

/**
 * 草稿卡片上的槽位标签，与 App 的 OutfitDraftCard 相同。
 * 有中层时，上装标为「打底」。没有槽位信息的成员退回到分类名称。
 */
export function memberLabels(members: ApiOutfitMember[], categoryName: (category: string) => string): string[] {
  const hasMidLayer = members.some((member) => member.slot === 'midLayer')
  return members.map((member) => {
    switch (member.slot) {
      case 'outerwear':
        return '外套'
      case 'midLayer':
        return '中层'
      case 'top':
        return hasMidLayer ? '打底' : '上装'
      case 'bottom':
        return '下装'
      case 'socks':
        return '袜子'
      case 'shoes':
        return '鞋子'
      case 'accessory':
        return '配饰'
      default:
        return categoryName(member.item.category)
    }
  })
}

/** 提交给服务端的成员列表，保留槽位。 */
export function toMembers(members: ApiOutfitMember[]): ApiMember[] {
  return members.map((member) => (member.slot ? { itemId: member.item.id, slot: member.slot } : { itemId: member.item.id }))
}

/**
 * 自由拼搭的槽位顺序，与 App 的 ManualOutfitBuilderView 相同，也是草稿 allItems 的顺序。
 * 每个槽位对应一个分类，槽位原始值与分类原始值相同。
 */
export const MANUAL_SLOT_CATEGORIES = ['outerwear', 'top', 'bottom', 'socks', 'shoes', 'accessory'] as const

/** 必选槽位全部选好后才能收藏或穿着。必选分类来自服务端元数据。 */
export function isManualComplete(picked: Record<string, ApiItem | undefined>, requiredCategories: string[]): boolean {
  return requiredCategories.every((category) => picked[category] !== undefined)
}

/** 按槽位顺序列出已选单品。 */
export function manualMembers(picked: Record<string, ApiItem | undefined>): ApiOutfitMember[] {
  return MANUAL_SLOT_CATEGORIES.flatMap((slot) => {
    const item = picked[slot]
    return item ? [{ slot, item }] : []
  })
}
