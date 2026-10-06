import type { ApiOutfitMember } from '../../api/types'
import { useMeta } from '../../app/meta'
import { ItemImage } from '../wardrobe/ItemImage'
import { memberLabels } from './outfitSlots'

/** 一套穿搭草稿的卡片，对应 App 的 OutfitDraftCard：列出各槽位单品，并提供「加入收藏」「今天穿这套」。 */
export function OutfitDraftCard({
  members,
  onFavorite,
  onWear,
  busy,
}: {
  members: ApiOutfitMember[]
  onFavorite?: () => void
  onWear?: () => void
  busy?: boolean
}) {
  const meta = useMeta()
  const labels = memberLabels(members, (category) => meta.name('category', category))
  return (
    <article className="panel draft-card" data-testid="outfit-draft">
      <ul className="draft-grid">
        {members.map((member, index) => (
          <li key={member.item.id} title={member.item.title}>
            <ItemImage item={member.item} className="thumb" />
            <span className="draft-label">{labels[index]}</span>
          </li>
        ))}
      </ul>
      {(onFavorite || onWear) && (
        <div className="row-buttons">
          {onFavorite && (
            <button type="button" className="button" onClick={onFavorite} disabled={busy}>
              加入收藏
            </button>
          )}
          {onWear && (
            <button type="button" className="button button-primary" onClick={onWear} disabled={busy}>
              今天穿这套
            </button>
          )}
        </div>
      )}
    </article>
  )
}
