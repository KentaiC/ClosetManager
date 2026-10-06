import { describe, expect, it } from 'vitest'
import { metaFixture } from '../../test/fixtures'
import { swatchColor, tileTextColor } from './colors'
import { dateKey, firstDayOfWeek, heatmapDays, intensity } from './heatmap'

describe('heatmapDays', () => {
  // 2026-10-06 是星期二；往前 111 天是 2026-06-17，星期三。
  const today = new Date(2026, 9, 6, 15, 30)

  it('aligns the first column to the week start and ends today', () => {
    const mondayFirst = heatmapDays(today, 16, 1)
    expect(dateKey(mondayFirst[0]!)).toBe('2026-06-15')
    expect(mondayFirst[0]!.getDay()).toBe(1)
    expect(dateKey(mondayFirst.at(-1)!)).toBe('2026-10-06')
    expect(mondayFirst).toHaveLength(114)

    const sundayFirst = heatmapDays(today, 16, 0)
    expect(dateKey(sundayFirst[0]!)).toBe('2026-06-14')
    expect(sundayFirst).toHaveLength(115)
  })

  it('lists consecutive calendar days without gaps or repeats', () => {
    const keys = heatmapDays(today, 16, 1).map(dateKey)
    expect(new Set(keys).size).toBe(keys.length)
    expect(keys).toContain('2026-07-01')
    expect(keys).toContain('2026-08-31')
    expect(keys).toContain('2026-09-01')
  })
})

describe('heatmap helpers', () => {
  it('formats local date keys', () => {
    expect(dateKey(new Date(2026, 0, 5, 23, 59))).toBe('2026-01-05')
  })

  it('uses the App intensity steps', () => {
    expect([0, 1, 2, 3, 9].map(intensity)).toEqual([0, 1, 2, 3, 3])
  })

  it('reads the week start from the locale and falls back to Sunday', () => {
    const value = firstDayOfWeek('zh-CN')
    expect(Number.isInteger(value) && value >= 0 && value <= 6).toBe(true)
    expect(firstDayOfWeek('!!')).toBe(0)
  })
})

describe('colour swatches', () => {
  it('has a swatch for every colour category in the metadata', () => {
    for (const option of metaFixture.colorCategories) expect(swatchColor(option.value)).toMatch(/^#[0-9A-F]{6}$/)
    expect(swatchColor('black')).toBe('#000000')
    expect(swatchColor('white')).toBe('#EBEBEB')
  })

  it('uses dark text on light tiles and white text on dark tiles', () => {
    expect(['white', 'beige', 'yellow', 'gray', 'pink', 'cyan'].map(tileTextColor)).toEqual(Array(6).fill('#000000'))
    expect(['black', 'brown', 'red', 'orange', 'green', 'blue', 'purple', 'multicolor'].map(tileTextColor)).toEqual(Array(8).fill('#FFFFFF'))
  })
})
