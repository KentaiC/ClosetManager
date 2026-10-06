import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiItem } from '../../api/types'
import { useResource } from '../../api/useResource'
import { useCapabilities } from '../../app/capabilities'
import { ConfirmDialog } from '../../app/Dialog'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { Link } from '../../app/router'
import { useToast } from '../../app/toast'
import { ItemImage } from '../wardrobe/ItemImage'

/** 清理相似衣物，对应 App 的 DuplicationView：进入后自动检测，可重新检测，每件可删除。 */
export function SimilarItemsPage() {
  const capabilities = useCapabilities()
  const toast = useToast()
  const { invalidate } = useDataVersion()
  const [run, setRun] = useState(0)
  const result = useResource(() => (capabilities.similarityDetection ? api.similarItems() : Promise.resolve([])), [run])
  const [removed, setRemoved] = useState<Set<string>>(new Set())
  const [pending, setPending] = useState<ApiItem | null>(null)

  async function remove(item: ApiItem) {
    try {
      await api.deleteItem(item.id)
      setRemoved((current) => new Set(current).add(item.id))
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setPending(null)
    }
  }

  // 删除后从当前展示的组里移除，组内不足 2 件则整组移除，与 App 相同。
  const groups = (result.data ?? []).map((group) => group.filter((item) => !removed.has(item.id))).filter((group) => group.length >= 2)

  return (
    <section className="page">
      <Link to="/settings" className="back-link">
        返回设置
      </Link>
      <div className="page-heading">
        <h1 className="page-title">清理相似衣物</h1>
        {capabilities.similarityDetection && (
          <button type="button" className="button" disabled={result.loading} onClick={() => { setRemoved(new Set()); setRun(run + 1) }}>
            重新检测
          </button>
        )}
      </div>
      {!capabilities.similarityDetection ? (
        <EmptyState title="当前服务不支持相似检测" description="相似检测依赖 macOS 的 Vision 框架，请在 macOS 上运行 closet-server。" />
      ) : result.error ? (
        <ErrorPanel error={result.error} onRetry={result.reload} />
      ) : result.loading ? (
        <Loading label="正在分析相似度…" />
      ) : groups.length === 0 ? (
        <EmptyState title="没有发现相似单品" description="当前衣橱里没有颜色与款式高度相似的单品。" />
      ) : (
        <ul className="record-list">
          {groups.map((group, index) => (
            <li key={group[0]!.id} className="panel" data-testid="similar-group">
              <h2 className="field-title">
                相似组 {index + 1}（{group.length} 件）
              </h2>
              <div className="thumb-row">
                {group.map((item) => (
                  <div key={item.id} className="similar-item">
                    <ItemImage item={item} className="thumb" />
                    <span className="similar-name">{item.title}</span>
                    <button type="button" className="link-button danger" onClick={() => setPending(item)}>
                      删除
                    </button>
                  </div>
                ))}
              </div>
            </li>
          ))}
        </ul>
      )}
      {pending && (
        <ConfirmDialog
          title={`删除「${pending.title}」？`}
          message="删除后无法恢复。它在收藏穿搭与穿着记录中的位置会被移除，穿搭与记录本身保留。"
          confirmLabel="删除"
          onConfirm={() => remove(pending)}
          onCancel={() => setPending(null)}
        />
      )}
    </section>
  )
}
