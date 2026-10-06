import type { ApiItem } from '../api/types'
import { ItemImage } from '../features/wardrobe/ItemImage'

/** 一排单品缩略图，对应 App 的 ItemThumbnail 横向列表。 */
export function ItemThumbnails({ items, size = 64 }: { items: ApiItem[]; size?: number }) {
  return (
    <div className="thumb-row">
      {items.map((item) => (
        <div key={item.id} className="thumb-wrap" style={{ width: size, flexBasis: size }} title={item.title}>
          <ItemImage item={item} className="thumb" />
        </div>
      ))}
    </div>
  )
}
