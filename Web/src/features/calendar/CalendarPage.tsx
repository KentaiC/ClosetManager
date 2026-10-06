import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiWearRecord } from '../../api/types'
import { useResource } from '../../api/useResource'
import { ConfirmDialog } from '../../app/Dialog'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useToast } from '../../app/toast'
import { ItemThumbnails } from '../../components/ItemThumbnails'

/** 日历历史，对应 App 的 CalendarHistoryView：按日期倒序列出穿着记录。 */
export function CalendarPage() {
  const { version, invalidate } = useDataVersion()
  const toast = useToast()
  const records = useResource(() => api.wearRecords(), [version])
  const [pendingDelete, setPendingDelete] = useState<ApiWearRecord | null>(null)

  async function remove(record: ApiWearRecord) {
    try {
      await api.deleteWearRecord(record.id)
      invalidate()
    } catch (e) {
      toast(e instanceof Error ? e.message : String(e))
    } finally {
      setPendingDelete(null)
    }
  }

  return (
    <section className="page">
      <h1 className="page-title">日历</h1>
      {records.error ? (
        <ErrorPanel error={records.error} onRetry={records.reload} />
      ) : records.loading && !records.data ? (
        <Loading />
      ) : (records.data ?? []).length === 0 ? (
        <EmptyState title="还没有穿搭记录" description="在「穿搭」里选择「今天穿这套」，记录就会出现在这里。" />
      ) : (
        <ul className="record-list">
          {(records.data ?? []).map((record) => (
            <li key={record.id} className="panel" data-testid="wear-record">
              <div className="panel-header">
                <strong>{new Date(record.date).toLocaleDateString('zh-CN', { dateStyle: 'full' })}</strong>
                <span className="row-actions">
                  {record.isActive && <span className="badge-inline badge-active">正在穿</span>}
                  <button type="button" className="link-button danger" onClick={() => setPendingDelete(record)}>
                    删除
                  </button>
                </span>
              </div>
              <ItemThumbnails items={record.items} size={52} />
              {record.notes && <p className="muted">{record.notes}</p>}
            </li>
          ))}
        </ul>
      )}
      {pendingDelete && (
        <ConfirmDialog
          title="删除这条穿着记录？"
          message="删除后无法恢复。单品本身不受影响。"
          confirmLabel="删除"
          onConfirm={() => remove(pendingDelete)}
          onCancel={() => setPendingDelete(null)}
        />
      )}
    </section>
  )
}
