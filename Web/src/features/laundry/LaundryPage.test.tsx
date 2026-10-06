import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, json, laundryFixture, mockFetch, requestBodies, standardRoutes } from '../../test/fixtures'

function openLaundry() {
  window.history.replaceState(null, '', '/laundry')
  render(<App />)
}

describe('LaundryPage', () => {
  it('lists laundry items by last update with the retention warning', async () => {
    const calls = mockFetch({ ...standardRoutes, '/api/v1/items': () => json({ items: laundryFixture }) })
    openLaundry()
    const grid = await screen.findByTestId('laundry-grid')
    const card = within(grid).getByRole('button', { name: '下装' })
    expect(within(card).getByText('久置·快洗')).toBeInTheDocument()
    const request = calls.find((call) => call.url.pathname === '/api/v1/items')!
    expect(Object.fromEntries(request.url.searchParams)).toEqual({ status: 'inLaundry', sort: 'updatedAt' })
  })

  it('returns the selected items to the wardrobe and refreshes', async () => {
    let laundry = laundryFixture
    const calls = mockFetch({
      ...standardRoutes,
      '/api/v1/items': () => json({ items: laundry }),
      '/api/v1/laundry/return': byMethod({
        POST: () => {
          laundry = []
          return json({ items: laundryFixture.map((item) => ({ ...item, status: 'inWardrobe' })) })
        },
      }),
    })
    openLaundry()
    const wash = await screen.findByRole('button', { name: '洗净放回（0）' })
    expect(wash).toBeDisabled()
    const card = screen.getByRole('button', { name: '下装' })
    await userEvent.click(card)
    expect(card).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: '洗净放回（1）' }))
    expect(await screen.findByText('洗衣袋是空的')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/laundry/return')).toEqual([{ itemIds: [laundryFixture[0]!.id] }])
  })

  it('selects and clears all', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/items': () => json({ items: laundryFixture }) })
    openLaundry()
    await userEvent.click(await screen.findByRole('button', { name: '全选' }))
    expect(screen.getByRole('button', { name: '下装' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(screen.getByRole('button', { name: '全不选' }))
    expect(screen.getByRole('button', { name: '下装' })).toHaveAttribute('aria-pressed', 'false')
  })
})
