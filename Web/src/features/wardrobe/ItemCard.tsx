import type { ApiItem } from '../../api/types'
import { useMeta } from '../../app/meta'
import { Link } from '../../app/router'
import { ItemImage } from './ItemImage'

/**
 * 衣橱网格中的单品卡片，布局与 App 的 ItemCard 一致：
 * 主色独占卡片底部一行，不覆盖图片与文字；小图模式只保留图片与主色条。
 */
export function ItemCard({ item, compact }: { item: ApiItem; compact: boolean }) {
  const meta = useMeta()
  return (
    <Link to={`/items/${item.id}`} className={`item-card${compact ? ' item-card-compact' : ''}`} aria-label={item.title}>
      <div className="item-card-image-wrap">
        <ItemImage item={item} />
        {item.status === 'inLaundry' && (
          <span className="badge badge-laundry" title="洗衣袋">
            {compact ? '洗' : '洗衣袋'}
          </span>
        )}
      </div>
      {compact ? (
        <span className="color-bar" style={{ backgroundColor: item.dominantColor.hex }} />
      ) : (
        <div className="item-card-info">
          <span className="item-card-title">{item.title}</span>
          {item.scenarios.length > 0 && (
            <span className="item-card-meta">{item.scenarios.map((value) => meta.name('scenario', value)).join(' · ')}</span>
          )}
          <span className="color-row">
            <span className="swatch" style={{ backgroundColor: item.dominantColor.hex }} />
            {item.dominantColor.name}
          </span>
        </div>
      )}
    </Link>
  )
}
