import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { itemsFixture, json, mockFetch, searchCasualFixture, standardRoutes } from '../../test/fixtures'

function setup() {
  const calls = mockFetch({
    ...standardRoutes,
    '/api/v1/search': (url) => json({ items: url.searchParams.get('scenario') === 'casual' ? searchCasualFixture : itemsFixture }),
  })
  return calls
}

const lastSearch = (calls: ReturnType<typeof setup>) =>
  Object.fromEntries(calls.filter((call) => call.url.pathname === '/api/v1/search').at(-1)!.url.searchParams)

describe('SearchPage', () => {
  it('is reachable from the wardrobe toolbar', async () => {
    setup()
    render(<App />)
    await userEvent.click(await screen.findByRole('link', { name: '高级筛选' }))
    expect(await screen.findByRole('heading', { name: '高级筛选' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '衣橱' })).toHaveAttribute('aria-current', 'page')
  })

  it('combines the filters into one search request', async () => {
    const calls = setup()
    window.history.replaceState(null, '', '/search')
    render(<App />)
    expect(await screen.findByText('共 3 件')).toBeInTheDocument()
    expect(lastSearch(calls)).toEqual({})

    await userEvent.selectOptions(screen.getByLabelText('场景'), 'casual')
    expect(await screen.findByText('共 2 件')).toBeInTheDocument()
    await userEvent.selectOptions(screen.getByLabelText('主色'), 'white')
    await userEvent.click(screen.getByLabelText('仅防水单品'))
    await userEvent.click(screen.getByLabelText('过去 90 天未穿过（吃灰单品）'))
    expect(lastSearch(calls)).toEqual({ scenario: 'casual', colorCategory: 'white', waterproof: 'true', unwornDays: '90' })

    await userEvent.click(screen.getByRole('button', { name: '重置' }))
    expect(await screen.findByText('共 3 件')).toBeInTheDocument()
    expect(lastSearch(calls)).toEqual({})
  })

  it('shows the empty result state', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/search': () => json({ items: [] }) })
    window.history.replaceState(null, '', '/search')
    render(<App />)
    expect(await screen.findByText('没有符合条件的单品')).toBeInTheDocument()
  })
})
