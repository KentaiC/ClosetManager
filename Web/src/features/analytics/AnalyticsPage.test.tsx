import { render, screen, within } from '@testing-library/react'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { App } from '../../App'
import { analyticsFixture, json, mockFetch, standardRoutes } from '../../test/fixtures'

function openAnalytics() {
  window.history.replaceState(null, '', '/analytics')
  render(<App />)
}

describe('AnalyticsPage', () => {
  beforeEach(() => {
    vi.useFakeTimers({ toFake: ['Date'] })
    vi.setSystemTime(new Date(2026, 6, 10, 12, 0))
  })
  afterEach(() => vi.useRealTimers())

  it('renders the four App dashboard cards from server data', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/analytics': () => json(analyticsFixture) })
    openAnalytics()
    expect(await screen.findByRole('heading', { name: '看板' })).toBeInTheDocument()
    expect(screen.getAllByRole('heading', { level: 2 }).map((heading) => heading.textContent)).toEqual([
      '衣橱库存透视',
      '衣橱颜色占比',
      '色彩偏好分析',
      '穿着活跃度',
    ])

    const inventory = screen.getByRole('list', { name: '各分类件数' })
    expect(within(inventory).getAllByRole('listitem').map((row) => row.textContent)).toEqual(['上装1', '下装1', '鞋子1'])

    const tiles = within(screen.getByRole('list', { name: '衣橱颜色占比' })).getAllByRole('listitem')
    expect(tiles.map((tile) => tile.getAttribute('aria-label'))).toEqual(['棕色 1 件', '蓝色 1 件', '白色 1 件'])

    const colors = screen.getByRole('list', { name: '最常穿的颜色' })
    expect(within(colors).getAllByRole('listitem').map((row) => row.textContent)).toEqual(['白色2', '蓝色1', '棕色1'])
  })

  it('colours heatmap days by wear count', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/analytics': () => json(analyticsFixture) })
    openAnalytics()
    const heatmap = await screen.findByRole('list', { name: '最近 16 周的穿着次数' })
    const cell = (date: string) => heatmap.querySelector(`[data-date="${date}"]`)
    expect(cell('2026-07-01')).toHaveClass('heat-1')
    expect(cell('2026-06-24')).toHaveClass('heat-1')
    expect(cell('2026-07-02')).toHaveClass('heat-0')
    expect(cell('2026-07-10')).not.toBeNull()
    expect(cell('2026-07-11')).toBeNull()
  })

  it('shows placeholders when there is no data', async () => {
    mockFetch({
      ...standardRoutes,
      '/api/v1/analytics': () => json({ inventory: [], colorInventory: [], colorFrequency: [], dailyActivity: [] }),
    })
    openAnalytics()
    expect(await screen.findAllByText('衣橱还没有单品')).toHaveLength(2)
    expect(screen.getAllByText('还没有穿搭记录')).toHaveLength(2)
  })
})
