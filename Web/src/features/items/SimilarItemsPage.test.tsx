import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, fixtureItem, json, macHealthFixture, mockFetch, noContent, standardRoutes } from '../../test/fixtures'

describe('SimilarItemsPage', () => {
  const tee = fixtureItem('白色T恤')
  const boots = fixtureItem('防水靴')
  const bottom = fixtureItem('下装')

  it('explains that detection needs macOS', async () => {
    const calls = mockFetch(standardRoutes)
    window.history.replaceState(null, '', '/similar')
    render(<App />)
    expect(await screen.findByText('当前服务不支持相似检测')).toBeInTheDocument()
    expect(calls.some((call) => call.url.pathname === '/api/v1/similar-items')).toBe(false)
    expect(screen.getByRole('link', { name: '设置' })).toHaveClass('active')
  })

  it('shows groups, deletes with confirmation and drops groups below two', async () => {
    let groups = [[tee, boots, bottom]]
    const calls = mockFetch({
      ...standardRoutes,
      '/api/v1/health': () => json(macHealthFixture),
      '/api/v1/similar-items': () => json({ groups }),
      [`/api/v1/items/${tee.id}`]: byMethod({ DELETE: noContent }),
      [`/api/v1/items/${boots.id}`]: byMethod({ DELETE: noContent }),
    })
    window.history.replaceState(null, '', '/similar')
    render(<App />)
    const group = await screen.findByTestId('similar-group')
    expect(within(group).getByText('相似组 1（3 件）')).toBeInTheDocument()

    await userEvent.click(within(group).getAllByRole('button', { name: '删除' })[0]!)
    await userEvent.click(within(screen.getByRole('dialog', { name: '删除「白色T恤」？' })).getByRole('button', { name: '删除' }))
    expect(await screen.findByText('相似组 1（2 件）')).toBeInTheDocument()

    await userEvent.click(within(screen.getByTestId('similar-group')).getAllByRole('button', { name: '删除' })[0]!)
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: '删除' }))
    expect(await screen.findByText('没有发现相似单品')).toBeInTheDocument()
    expect(calls.filter((call) => call.init?.method === 'DELETE')).toHaveLength(2)

    groups = [[tee, boots]]
    await userEvent.click(screen.getByRole('button', { name: '重新检测' }))
    expect(await screen.findByText('相似组 1（2 件）')).toBeInTheDocument()
    expect(calls.filter((call) => call.url.pathname === '/api/v1/similar-items')).toHaveLength(2)
  })
})
