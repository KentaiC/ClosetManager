import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiItem } from '../../api/types'
import { useResource } from '../../api/useResource'
import { ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { useToast } from '../../app/toast'
import { ItemImage } from '../wardrobe/ItemImage'
import { isManualComplete, manualMembers, MANUAL_SLOT_CATEGORIES, toMembers } from './outfitSlots'

/**
 * 自由拼搭，对应 App 的 ManualOutfitBuilderView。
 * 上装、下装、鞋子必选，外套、袜子、配饰可选；只能选择在衣橱中的单品。
 * 收藏时来源记为「手动拼搭」，App 记为「算法生成」（审计 M-05）。
 */
export function ManualBuilder() {
  const meta = useMeta()
  const toast = useToast()
  const { version, invalidate } = useDataVersion()
  const items = useResource(() => api.items({ status: 'inWardrobe' }), [version])
  const [picked, setPicked] = useState<Record<string, ApiItem | undefined>>({})
  const [busy, setBusy] = useState(false)

  const required = meta.meta.categories.filter((category) => category.isRequiredInOutfit).map((category) => category.value)
  const complete = isManualComplete(picked, required)

  function toggle(category: string, item: ApiItem) {
    setPicked((current) => ({ ...current, [category]: current[category]?.id === item.id ? undefined : item }))
  }

  async function act(action: () => Promise<unknown>, message: string) {
    setBusy(true)
    try {
      await action()
      toast(message)
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  if (items.error) return <ErrorPanel error={items.error} onRetry={items.reload} />
  if (items.loading && !items.data) return <Loading />
  const available = items.data ?? []
  const members = toMembers(manualMembers(picked))

  return (
    <div className="stack">
      {MANUAL_SLOT_CATEGORIES.map((category) => {
        const candidates = available.filter((item) => item.category === category)
        const name = meta.name('category', category)
        return (
          <section key={category} className="slot-picker" aria-label={name}>
            <div className="panel-header">
              <h2 className="field-title">
                {name}
                {required.includes(category) && <span className="required-tag">必选</span>}
              </h2>
              {picked[category] && (
                <button type="button" className="link-button" onClick={() => setPicked((current) => ({ ...current, [category]: undefined }))}>
                  清除
                </button>
              )}
            </div>
            {candidates.length === 0 ? (
              <p className="hint">衣橱里暂无可用的{name}</p>
            ) : (
              <div className="thumb-row">
                {candidates.map((item) => {
                  const selected = picked[category]?.id === item.id
                  return (
                    <button
                      key={item.id}
                      type="button"
                      className={`thumb-button${selected ? ' selected' : ''}`}
                      aria-pressed={selected}
                      aria-label={item.title}
                      title={item.title}
                      onClick={() => toggle(category, item)}
                    >
                      <ItemImage item={item} className="thumb" />
                    </button>
                  )
                })}
              </div>
            )}
          </section>
        )
      })}
      <div className="row-buttons">
        <button
          type="button"
          className="button"
          disabled={!complete || busy}
          onClick={() => act(() => api.createOutfit({ source: 'manual', members }), '已加入收藏')}
        >
          加入收藏
        </button>
        <button
          type="button"
          className="button button-primary"
          disabled={!complete || busy}
          onClick={() => act(() => api.wear(members), '已设为今天穿这套')}
        >
          今天穿这套
        </button>
      </div>
    </div>
  )
}
