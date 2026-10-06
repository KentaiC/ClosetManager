import { describe, expect, it } from 'vitest'
import { layoutTreemap } from './treemap'

const wide = { x: 0, y: 0, width: 600, height: 240 }

describe('layoutTreemap', () => {
  it('places nothing for no tiles and the whole rect for one tile', () => {
    expect(layoutTreemap([], wide)).toEqual([])
    expect(layoutTreemap([{ count: 4 }], wide)).toEqual([{ tile: { count: 4 }, rect: wide }])
  })

  it('splits along the longer side in proportion to the weights', () => {
    expect(layoutTreemap([{ count: 3 }, { count: 1 }], wide).map((placed) => placed.rect)).toEqual([
      { x: 0, y: 0, width: 450, height: 240 },
      { x: 450, y: 0, width: 150, height: 240 },
    ])
    const tall = { x: 0, y: 0, width: 100, height: 400 }
    expect(layoutTreemap([{ count: 1 }, { count: 1 }], tall).map((placed) => placed.rect)).toEqual([
      { x: 0, y: 0, width: 100, height: 200 },
      { x: 0, y: 200, width: 100, height: 200 },
    ])
  })

  it('weights counts below one as one', () => {
    expect(layoutTreemap([{ count: 0 }, { count: -2 }], wide).map((placed) => placed.rect.width)).toEqual([300, 300])
  })

  it('keeps every area proportional to its count and covers the rect', () => {
    const tiles = [5, 3, 2, 1, 1].map((count, index) => ({ count, index }))
    const placed = layoutTreemap(tiles, wide)
    expect(placed.map((entry) => entry.tile.index)).toEqual([0, 1, 2, 3, 4])
    const totalArea = wide.width * wide.height
    for (const { tile, rect } of placed) {
      expect(rect.width * rect.height).toBeCloseTo((tile.count / 12) * totalArea, 6)
      expect(rect.x).toBeGreaterThanOrEqual(0)
      expect(rect.y).toBeGreaterThanOrEqual(0)
      expect(rect.x + rect.width).toBeLessThanOrEqual(wide.width + 1e-9)
      expect(rect.y + rect.height).toBeLessThanOrEqual(wide.height + 1e-9)
    }
  })
})
