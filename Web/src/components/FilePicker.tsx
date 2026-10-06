import { useRef, useState, type DragEvent, type ReactNode } from 'react'

/** 服务端接受的图片类型。HEIC 在部分系统上没有 MIME 类型，所以同时列出扩展名。 */
export const IMAGE_ACCEPT = 'image/jpeg,image/png,image/heic,image/heif,image/webp,.heic,.heif'

/** 按钮触发的文件选择。选择后清空输入框，同一个文件可以再次选择。 */
export function FilePicker({
  label,
  accept,
  multiple = false,
  disabled = false,
  className = 'button',
  onFiles,
}: {
  label: string
  accept: string
  multiple?: boolean
  disabled?: boolean
  className?: string
  onFiles: (files: File[]) => void
}) {
  const input = useRef<HTMLInputElement>(null)
  return (
    <>
      <button type="button" className={className} disabled={disabled} onClick={() => input.current?.click()}>
        {label}
      </button>
      <input
        ref={input}
        type="file"
        hidden
        accept={accept}
        multiple={multiple}
        aria-label={label}
        disabled={disabled}
        onChange={(event) => {
          const files = Array.from(event.target.files ?? [])
          event.target.value = ''
          if (files.length > 0) onFiles(files)
        }}
      />
    </>
  )
}

/** 拖放区域，对应 App 衣橱页的拖拽录入。 */
export function DropZone({ onFiles, children, label }: { onFiles: (files: File[]) => void; children: ReactNode; label: string }) {
  const [active, setActive] = useState(false)
  function over(event: DragEvent) {
    event.preventDefault()
    setActive(true)
  }
  function drop(event: DragEvent) {
    event.preventDefault()
    setActive(false)
    const files = Array.from(event.dataTransfer.files)
    if (files.length > 0) onFiles(files)
  }
  return (
    <div
      className={`drop-zone${active ? ' active' : ''}`}
      aria-label={label}
      onDragOver={over}
      onDragLeave={() => setActive(false)}
      onDrop={drop}
    >
      {children}
    </div>
  )
}
