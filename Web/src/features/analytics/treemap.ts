export interface Rect {
  x: number
  y: number
  width: number
  height: number
}

/**
 * 颜色树形图的递归二分切割布局，移植自 App 的 ColorTreemapView.layout。
 * 按权重把列表分成前后两组，沿较长边按权重比例切开，递归到单块。
 * 件数小于 1 的块按 1 计权重。调用方负责先按件数从多到少排序。
 */
export function layoutTreemap<T extends { count: number }>(tiles: readonly T[], rect: Rect): { tile: T; rect: Rect }[] {
  const first = tiles[0]
  if (first === undefined) return []
  if (tiles.length === 1) return [{ tile: first, rect }]

  const weight = (tile: T) => Math.max(tile.count, 1)
  const total = tiles.reduce((sum, tile) => sum + weight(tile), 0)
  const firstGroup: T[] = []
  let accumulated = 0
  for (const tile of tiles) {
    if (accumulated >= total / 2 && firstGroup.length > 0) break
    firstGroup.push(tile)
    accumulated += weight(tile)
  }
  if (firstGroup.length === tiles.length) firstGroup.pop()
  const secondGroup = tiles.slice(firstGroup.length)

  const firstWeight = firstGroup.reduce((sum, tile) => sum + weight(tile), 0)
  const ratio = total > 0 ? firstWeight / total : 0.5

  let r1: Rect
  let r2: Rect
  if (rect.width >= rect.height) {
    const w1 = rect.width * ratio
    r1 = { x: rect.x, y: rect.y, width: w1, height: rect.height }
    r2 = { x: rect.x + w1, y: rect.y, width: rect.width - w1, height: rect.height }
  } else {
    const h1 = rect.height * ratio
    r1 = { x: rect.x, y: rect.y, width: rect.width, height: h1 }
    r2 = { x: rect.x, y: rect.y + h1, width: rect.width, height: rect.height - h1 }
  }
  return [...layoutTreemap(firstGroup, r1), ...layoutTreemap(secondGroup, r2)]
}
