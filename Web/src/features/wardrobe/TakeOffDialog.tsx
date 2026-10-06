import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiWearRecord } from '../../api/types'
import { Dialog } from '../../app/Dialog'
import { useMeta } from '../../app/meta'
import { ItemImage } from './ItemImage'

/**
 * 「脱下穿搭」对话框，对应 App 的 TakeOffSheet：
 * 上装、下装、袜子默认勾选，其余默认不勾选；「一键全扔」把全部单品放进洗衣袋，「按勾选脱下」只放勾选的。
 */
export function TakeOffDialog({ record, onClose, onDone }: { record: ApiWearRecord; onClose: () => void; onDone: () => void }) {
  const meta = useMeta()
  const washByDefault = new Set(meta.meta.categories.filter((c) => c.washByDefaultOnTakeOff).map((c) => c.value))
  const [selected, setSelected] = useState<Set<string>>(
    () => new Set(record.items.filter((item) => washByDefault.has(item.category)).map((item) => item.id)),
  )
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  function toggle(id: string) {
    setSelected((current) => {
      const next = new Set(current)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  async function confirm(all: boolean) {
    setBusy(true)
    setError(null)
    try {
      await api.takeOff(record.id, all ? record.items.map((item) => item.id) : [...selected])
      onDone()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setBusy(false)
    }
  }

  return (
    <Dialog
      title="脱下穿搭"
      onClose={onClose}
      footer={
        <>
          <button type="button" className="button" onClick={onClose}>
            取消
          </button>
          <button type="button" className="button" onClick={() => confirm(false)} disabled={busy}>
            按勾选脱下
          </button>
          <button type="button" className="button button-warning" onClick={() => confirm(true)} disabled={busy}>
            一键全扔进洗衣袋
          </button>
        </>
      }
    >
      <p className="muted">勾选要扔进洗衣袋的单品。未勾选的将直接回到衣橱。上装 / 下装 / 袜子已按生活常识默认勾选。</p>
      <ul className="check-list">
        {record.items.map((item) => (
          <li key={item.id}>
            <label>
              <input type="checkbox" checked={selected.has(item.id)} onChange={() => toggle(item.id)} />
              <ItemImage item={item} className="thumb" />
              <span>
                <span className="check-title">{item.title}</span>
                <span className="muted">
                  {meta.name('category', item.category)}
                  {item.subtype ? ` · ${meta.name('subtype', item.subtype)}` : ''}
                </span>
              </span>
            </label>
          </li>
        ))}
      </ul>
      {error && <p className="form-error" role="alert">{error}</p>}
    </Dialog>
  )
}
