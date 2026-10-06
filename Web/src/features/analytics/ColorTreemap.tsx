import { useEffect, useRef, useState } from 'react'
import { layoutTreemap } from './treemap'

export interface TreemapTile {
  key: string
  label: string
  count: number
  fill: string
  text: string
}

const HEIGHT = 240

/** 颜色树形图，对应 App 的 ColorTreemapView：色块面积与件数成正比，块足够大时显示名称与件数。 */
export function ColorTreemap({ tiles }: { tiles: TreemapTile[] }) {
  const container = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(600)

  useEffect(() => {
    const element = container.current
    if (!element) return
    const measure = () => {
      if (element.clientWidth > 0) setWidth(element.clientWidth)
    }
    measure()
    if (typeof ResizeObserver === 'undefined') return
    const observer = new ResizeObserver(measure)
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  // 按件数从多到少排序；件数相同时保持服务端返回的顺序。
  const sorted = [...tiles].sort((a, b) => b.count - a.count)
  const placed = layoutTreemap(sorted, { x: 0, y: 0, width, height: HEIGHT })

  return (
    <div className="treemap" ref={container} role="list" aria-label="衣橱颜色占比">
      {placed.map(({ tile, rect }) => (
        <div
          key={tile.key}
          role="listitem"
          className="treemap-tile"
          title={`${tile.label}：${tile.count} 件`}
          aria-label={`${tile.label} ${tile.count} 件`}
          style={{
            left: rect.x + 1,
            top: rect.y + 1,
            width: Math.max(rect.width - 2, 0),
            height: Math.max(rect.height - 2, 0),
            backgroundColor: tile.fill,
            color: tile.text,
          }}
        >
          {rect.width > 44 && rect.height > 28 && (
            <>
              <strong>{tile.label}</strong>
              <span>{tile.count}</span>
            </>
          )}
        </div>
      ))}
    </div>
  )
}
