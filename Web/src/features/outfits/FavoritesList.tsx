import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiOutfit } from '../../api/types'
import { useResource } from '../../api/useResource'
import { ConfirmDialog } from '../../app/Dialog'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { useToast } from '../../app/toast'
import { ItemThumbnails } from '../../components/ItemThumbnails'

/** 收藏夹，对应 App 的 FavoritesView：可「今天穿这套」或删除。 */
export function FavoritesList() {
  const meta = useMeta()
  const toast = useToast()
  const { version, invalidate } = useDataVersion()
  const favorites = useResource(() => api.outfits(true), [version])
  const [pendingDelete, setPendingDelete] = useState<ApiOutfit | null>(null)
  const [busy, setBusy] = useState(false)

  async function wear(outfit: ApiOutfit) {
    setBusy(true)
    try {
      await api.wearOutfit(outfit.id)
      toast('已设为今天穿这套')
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  async function remove(outfit: ApiOutfit) {
    try {
      await api.deleteOutfit(outfit.id)
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setPendingDelete(null)
    }
  }

  if (favorites.error) return <ErrorPanel error={favorites.error} onRetry={favorites.reload} />
  if (favorites.loading && !favorites.data) return <Loading />
  const list = favorites.data ?? []
  if (list.length === 0) {
    return <EmptyState title="还没有收藏的穿搭" description="在「智能生成」或「自由拼搭」里把喜欢的组合加入收藏。" />
  }
  return (
    <>
      <ul className="record-list">
        {list.map((outfit) => (
          <li key={outfit.id} className="panel" data-testid="favorite-outfit">
            <ItemThumbnails items={outfit.members.map((member) => member.item)} size={56} />
            {outfit.missingRequiredCategories.length > 0 && (
              <p className="hint warning">
                缺少：{outfit.missingRequiredCategories.map((c) => meta.name('category', c)).join('、')}。相关单品可能已被删除。
              </p>
            )}
            <div className="panel-header">
              <span className="muted">{meta.name('scenario', outfit.targetScenario)}</span>
              <span className="row-actions">
                <button type="button" className="link-button danger" onClick={() => setPendingDelete(outfit)}>
                  删除
                </button>
                <button type="button" className="button button-primary" onClick={() => wear(outfit)} disabled={busy}>
                  今天穿这套
                </button>
              </span>
            </div>
          </li>
        ))}
      </ul>
      {pendingDelete && (
        <ConfirmDialog
          title="删除这套收藏？"
          message="删除后无法恢复。单品和穿着记录不受影响。"
          confirmLabel="删除"
          onConfirm={() => remove(pendingDelete)}
          onCancel={() => setPendingDelete(null)}
        />
      )}
    </>
  )
}
