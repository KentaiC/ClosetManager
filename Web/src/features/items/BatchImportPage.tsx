import { useState } from 'react'
import { api } from '../../api/client'
import { useDataVersion } from '../../app/dataVersion'
import { Link, navigate } from '../../app/router'
import { useToast } from '../../app/toast'
import { DropZone, FilePicker, IMAGE_ACCEPT } from '../../components/FilePicker'
import { ItemEditor } from '../wardrobe/ItemEditor'

/**
 * 批量录入，对应 App 的 BatchImportView：保留全部所选图片，逐张抠图取色并打标签，
 * 「保存并下一件」推进队列直至清空，「跳过这张」不保存。
 */
export function BatchImportPage() {
  const { invalidate } = useDataVersion()
  const toast = useToast()
  const [queue, setQueue] = useState<File[]>([])
  const [index, setIndex] = useState(0)
  const [saved, setSaved] = useState(0)
  const isLast = index >= queue.length - 1

  function advance(savedNow: number) {
    if (isLast) {
      invalidate()
      toast(`已保存 ${savedNow} 件`)
      navigate('/')
    } else {
      setIndex(index + 1)
    }
  }

  if (queue.length === 0) {
    return (
      <section className="page">
        <Link to="/" className="back-link">
          返回衣橱
        </Link>
        <h1 className="page-title">批量录入</h1>
        <DropZone label="拖放图片到这里" onFiles={(files) => setQueue(files)}>
          <p>把多张图片拖到这里，或者</p>
          <FilePicker label="选择多张图片" accept={IMAGE_ACCEPT} multiple className="button button-primary" onFiles={(files) => setQueue(files)} />
          <p className="hint">选好后逐张抠图取色并打标签，可以随时跳过或退出。</p>
        </DropZone>
      </section>
    )
  }

  return (
    <section className="page">
      <div className="page-heading">
        <h1 className="page-title">批量录入</h1>
        <button type="button" className="button" onClick={() => { if (saved > 0) invalidate(); navigate('/') }}>
          退出
        </button>
      </div>
      <div className="batch-progress">
        <span>
          第 {Math.min(index + 1, queue.length)} / {queue.length} 件
        </span>
        <progress value={index} max={Math.max(queue.length, 1)} aria-label="批量录入进度" />
      </div>
      <ItemEditor
        key={index}
        initialFile={queue[index]}
        allowsImagePicker={false}
        onSubmit={(update) => api.createItem(update)}
        onSaved={() => {
          const next = saved + 1
          setSaved(next)
          advance(next)
        }}
        renderActions={({ canSave, saving, save }) => (
          <div className="row-buttons sticky-actions">
            <button type="button" className="button" onClick={() => advance(saved)} disabled={saving}>
              跳过这张
            </button>
            <button type="button" className="button button-primary" onClick={save} disabled={!canSave}>
              {isLast ? '保存并完成' : '保存并下一件'}
            </button>
          </div>
        )}
      />
    </section>
  )
}
