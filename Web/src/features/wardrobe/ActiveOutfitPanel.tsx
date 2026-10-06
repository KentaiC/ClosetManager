import { useState } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { ErrorPanel } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { ItemThumbnails } from '../../components/ItemThumbnails'
import { TakeOffDialog } from './TakeOffDialog'

/** 「目前正在穿」看板，对应 App 的 ActiveOutfitWidget。 */
export function ActiveOutfitPanel() {
  const { version, invalidate } = useDataVersion()
  const active = useResource(() => api.activeWearRecord(), [version])
  const [takingOff, setTakingOff] = useState(false)
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
      <ItemThumbnails items={record.items} />
      <button type="button" className="button button-warning button-block" onClick={() => setTakingOff(true)}>
        脱下并扔进洗衣袋
      </button>
      {takingOff && (
        <TakeOffDialog
          record={record}
          onClose={() => setTakingOff(false)}
          onDone={() => {
            setTakingOff(false)
            invalidate()
          }}
        />
      )}
    </div>
  )
}
