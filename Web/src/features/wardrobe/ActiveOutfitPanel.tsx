import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { ErrorPanel } from '../../app/Feedback'
import { ItemImage } from './ItemImage'

/** 「目前正在穿」看板，对应 App 的 ActiveOutfitWidget。脱下操作在后续阶段接入。 */
export function ActiveOutfitPanel() {
  const active = useResource(() => api.activeWearRecord(), [])
  if (active.error) return <ErrorPanel error={active.error} onRetry={active.reload} />
  const record = active.data
  if (!record) {
    return (
      <div className="panel panel-muted" data-testid="active-outfit-empty">
        {active.loading ? '正在读取当前穿搭…' : '今天尚未选择穿搭'}
      </div>
    )
  }
  return (
    <div className="panel" data-testid="active-outfit">
      <div className="panel-header">
        <strong>目前正在穿</strong>
        <span className="muted">{new Date(record.date).toLocaleDateString('zh-CN')}</span>
      </div>
      <div className="thumb-row">
        {record.items.map((item) => (
          <ItemImage key={item.id} item={item} className="thumb" />
        ))}
      </div>
    </div>
  )
}
