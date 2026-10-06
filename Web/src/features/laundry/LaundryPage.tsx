import { useEffect, useMemo, useState } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useToast } from '../../app/toast'
import { ItemImage } from '../wardrobe/ItemImage'

/** 洗衣房，对应 App 的 LaundryView：勾选后「洗净放回」，入袋超过阈值显示预警。 */
export function LaundryPage() {
  const { version, invalidate } = useDataVersion()
  const toast = useToast()
  const laundry = useResource(() => api.items({ status: 'inLaundry', sort: 'updatedAt' }), [version])
  const [selection, setSelection] = useState<Set<string>>(new Set())
  const [busy, setBusy] = useState(false)
  const items = useMemo(() => laundry.data ?? [], [laundry.data])

  // 列表变化时清掉已不存在的选中项（与 App 相同）。
  useEffect(() => {
    setSelection((current) => new Set([...current].filter((id) => items.some((item) => item.id === id))))
  }, [items])

  const allSelected = items.length > 0 && selection.size === items.length

  function toggle(id: string) {
    setSelection((current) => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function wash() {
    setBusy(true)
    try {
      await api.returnFromLaundry([...selection])
      setSelection(new Set())
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  return (
    <section className="page">
      <div className="page-heading">
        <h1 className="page-title">洗衣房</h1>
        {items.length > 0 && (
          <button type="button" className="button" onClick={() => setSelection(allSelected ? new Set() : new Set(items.map((i) => i.id)))}>
            {allSelected ? '全不选' : '全选'}
          </button>
        )}
      </div>
      {laundry.error ? (
        <ErrorPanel error={laundry.error} onRetry={laundry.reload} />
      ) : laundry.loading && !laundry.data ? (
        <Loading />
      ) : items.length === 0 ? (
        <EmptyState title="洗衣袋是空的" description="被标记为「在洗衣袋」的单品会出现在这里。" />
      ) : (
        <>
          <div className="gallery gallery-medium" data-testid="laundry-grid">
            {items.map((item) => (
              <button
                key={item.id}
                type="button"
                className={`item-card selectable${selection.has(item.id) ? ' selected' : ''}`}
                aria-pressed={selection.has(item.id)}
                aria-label={item.title}
                onClick={() => toggle(item.id)}
              >
                <div className="item-card-image-wrap">
                  <ItemImage item={item} />
                  <span className="select-mark" aria-hidden="true">{selection.has(item.id) ? '✓' : ''}</span>
                  {item.laundryRetentionWarning && <span className="badge badge-warning">久置·快洗</span>}
                </div>
                <span className="item-card-title">{item.title}</span>
              </button>
            ))}
          </div>
          <div className="sticky-actions">
            <button type="button" className="button button-primary button-block" disabled={selection.size === 0 || busy} onClick={wash}>
              洗净放回（{selection.size}）
            </button>
          </div>
        </>
      )}
    </section>
  )
}
