import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { itemsFixture, json, mockFetch, standardRoutes } from '../../test/fixtures'

describe('WardrobePage', () => {
  it('shows only wardrobe items until laundry is toggled; luggage stays hidden', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    const gallery = await screen.findByTestId('gallery')
    expect(within(gallery).getAllByRole('link').map((link) => link.getAttribute('aria-label'))).toEqual(['白色T恤'])

    await userEvent.click(screen.getByLabelText('显示洗衣袋内衣物'))
    expect(screen.getByText('正在显示洗衣袋内衣物')).toBeInTheDocument()
    const labels = within(screen.getByTestId('gallery')).getAllByRole('link').map((link) => link.getAttribute('aria-label'))
    expect(labels).toEqual(['下装', '白色T恤'])
    expect(labels).not.toContain('防水靴')
    expect(screen.getByTitle('洗衣袋')).toBeInTheDocument()
  })

  it('filters by category chips built from server metadata', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    await screen.findByTestId('gallery')
    await userEvent.click(screen.getByRole('button', { name: '鞋子' }))
    expect(screen.getByText('该分类下没有可显示的单品')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '全部' }))
    expect(screen.getByTestId('gallery')).toBeInTheDocument()
  })

  it('renders scenario names and the colour row on cards', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    const card = await screen.findByRole('link', { name: '白色T恤' })
    expect(within(card).getByText('通勤 · 休闲')).toBeInTheDocument()
    expect(within(card).getByText('白色')).toBeInTheDocument()
  })

  it('persists the gallery size and switches to compact cards', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    await screen.findByTestId('gallery')
    await userEvent.click(screen.getByRole('button', { name: '小' }))
    expect(window.localStorage.getItem('galleryItemSize')).toBe('small')
    expect(screen.getByTestId('gallery')).toHaveClass('gallery-small')
    expect(screen.queryByText('通勤 · 休闲')).not.toBeInTheDocument()
  })

  it('shows the active outfit panel', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    const panel = await screen.findByTestId('active-outfit')
    expect(within(panel).getByText('目前正在穿')).toBeInTheDocument()
  })

  it('shows the empty wardrobe state', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/items': () => json({ items: [] }), '/api/v1/wear-records/active': () => json({}) })
    render(<App />)
    expect(await screen.findByText('衣橱还是空的')).toBeInTheDocument()
    expect(await screen.findByText('今天尚未选择穿搭')).toBeInTheDocument()
  })

  it('opens the read-only detail page from a card', async () => {
    mockFetch({
      ...standardRoutes,
      '/api/v1/items/7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E': () =>
        json(itemsFixture.find((item) => item.id === '7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E')),
    })
    render(<App />)
    await userEvent.click(await screen.findByRole('link', { name: '白色T恤' }))
    expect(await screen.findByRole('heading', { name: '白色T恤' })).toBeInTheDocument()
    expect(screen.getByText('上装 · T恤')).toBeInTheDocument()
    expect(screen.getByText('20（暖和）')).toBeInTheDocument()
    expect(screen.getByText('示例品牌')).toBeInTheDocument()
  })
})
