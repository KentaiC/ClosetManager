import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import {
  activeFixture,
  byMethod,
  draftsFixture,
  fixtureItem,
  itemsFixture,
  json,
  missingFixture,
  mockFetch,
  noContent,
  outfitsFixture,
  requestBodies,
  standardRoutes,
} from '../../test/fixtures'

const FAVORITE_ID = 'A1B2C3D4-E5F6-4A7B-8C9D-0E1F2A3B4C5D'
const draftMembers = draftsFixture.drafts[0]!.members.map((member) => ({ itemId: member.item.id, slot: member.slot }))

function routes(favorites = outfitsFixture) {
  return {
    ...standardRoutes,
    '/api/v1/outfit-suggestions': (url: URL) => json(url.searchParams.get('scenario') === 'casual' ? draftsFixture : missingFixture),
    '/api/v1/outfits': byMethod({ GET: () => json({ items: favorites }), POST: () => json(outfitsFixture[0]) }),
    [`/api/v1/outfits/${FAVORITE_ID}`]: byMethod({ DELETE: noContent }),
    [`/api/v1/outfits/${FAVORITE_ID}/wear`]: byMethod({ POST: () => json(activeFixture) }),
    '/api/v1/wear-records': byMethod({ POST: () => json(activeFixture) }),
  }
}

function openOutfits() {
  window.history.replaceState(null, '', '/outfits')
  render(<App />)
}

describe('OutfitsPage · 智能生成', () => {
  it('starts with 温和 and 休闲 and shows the drafts with slot labels', async () => {
    const calls = mockFetch(routes())
    openOutfits()
    expect(await screen.findByRole('heading', { name: '穿搭' })).toBeInTheDocument()
    expect(screen.getByRole('radio', { name: '温和' })).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByRole('radio', { name: '休闲' })).toHaveAttribute('aria-checked', 'true')
    expect(screen.getByText('选择上方条件后点「生成穿搭」。')).toBeInTheDocument()

    await userEvent.click(screen.getByRole('button', { name: '生成穿搭' }))
    const card = await screen.findByTestId('outfit-draft')
    expect(within(card).getAllByText(/^(上装|下装|鞋子)$/).map((label) => label.textContent)).toEqual(['上装', '下装', '鞋子'])
    const request = calls.find((call) => call.url.pathname === '/api/v1/outfit-suggestions')!
    expect(Object.fromEntries(request.url.searchParams)).toEqual({ warmth: 'mild', scenario: 'casual', requireWaterproof: 'false' })
  })

  it('saves a favourite with the conditions the drafts were generated under', async () => {
    const calls = mockFetch(routes())
    openOutfits()
    await userEvent.click(await screen.findByRole('button', { name: '生成穿搭' }))
    const card = await screen.findByTestId('outfit-draft')
    // 生成后再改条件，收藏仍记录生成时的条件。
    await userEvent.click(screen.getByRole('radio', { name: '通勤' }))
    await userEvent.click(screen.getByRole('radio', { name: '寒冷' }))
    await userEvent.click(within(card).getByRole('button', { name: '加入收藏' }))
    expect(await screen.findByText('已加入收藏')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/outfits')).toEqual([
      { source: 'generated', targetScenario: 'casual', targetWarmthLevel: 'mild', members: draftMembers },
    ])
  })

  it('wears a draft today', async () => {
    const calls = mockFetch(routes())
    openOutfits()
    await userEvent.click(await screen.findByRole('button', { name: '生成穿搭' }))
    await userEvent.click(within(await screen.findByTestId('outfit-draft')).getByRole('button', { name: '今天穿这套' }))
    expect(await screen.findByText('已设为今天穿这套')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/wear-records')).toEqual([{ members: draftMembers }])
  })

  it('explains which required categories are missing', async () => {
    const calls = mockFetch(routes())
    openOutfits()
    await userEvent.click(await screen.findByRole('radio', { name: '通勤' }))
    await userEvent.click(screen.getByLabelText('雨 / 雪天（强制防水外套与鞋子）'))
    await userEvent.click(screen.getByRole('button', { name: '生成穿搭' }))
    expect(await screen.findByText('缺少必选单品，无法生成')).toBeInTheDocument()
    expect(screen.getByText('当前条件下缺少：下装、鞋子。请先在衣橱补充对应单品。')).toBeInTheDocument()
    const request = calls.find((call) => call.url.pathname === '/api/v1/outfit-suggestions')!
    expect(request.url.searchParams.get('requireWaterproof')).toBe('true')
  })

  it('shows the no-match state when nothing fits', async () => {
    mockFetch({ ...routes(), '/api/v1/outfit-suggestions': () => json({ drafts: [], missingRequired: [] }) })
    openOutfits()
    await userEvent.click(await screen.findByRole('button', { name: '生成穿搭' }))
    expect(await screen.findByText('没有匹配的穿搭')).toBeInTheDocument()
  })
})

describe('OutfitsPage · 收藏夹', () => {
  it('wears and deletes a favourite', async () => {
    const calls = mockFetch(routes())
    openOutfits()
    await userEvent.click(await screen.findByRole('tab', { name: '收藏夹' }))
    const row = await screen.findByTestId('favorite-outfit')
    expect(within(row).getByText('休闲')).toBeInTheDocument()

    await userEvent.click(within(row).getByRole('button', { name: '今天穿这套' }))
    expect(await screen.findByText('已设为今天穿这套')).toBeInTheDocument()
    expect(calls.some((call) => call.init?.method === 'POST' && call.url.pathname === `/api/v1/outfits/${FAVORITE_ID}/wear`)).toBe(true)

    await userEvent.click(within(row).getByRole('button', { name: '删除' }))
    const dialog = screen.getByRole('dialog', { name: '删除这套收藏？' })
    await userEvent.click(within(dialog).getByRole('button', { name: '删除' }))
    expect(calls.some((call) => call.init?.method === 'DELETE' && call.url.pathname === `/api/v1/outfits/${FAVORITE_ID}`)).toBe(true)
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('shows the empty state', async () => {
    mockFetch(routes([]))
    openOutfits()
    await userEvent.click(await screen.findByRole('tab', { name: '收藏夹' }))
    expect(await screen.findByText('还没有收藏的穿搭')).toBeInTheDocument()
  })
})

describe('OutfitsPage · 自由拼搭', () => {
  // 样例中只有上装在衣橱；这里把三件都当作在衣橱，以便凑齐必选项。
  const available = itemsFixture.map((item) => ({ ...item, status: 'inWardrobe' }))

  it('requires top, bottom and shoes and saves the picks as a manual outfit', async () => {
    const calls = mockFetch({ ...routes(), '/api/v1/items': () => json({ items: available }) })
    openOutfits()
    await userEvent.click(await screen.findByRole('tab', { name: '自由拼搭' }))
    expect(await screen.findByText('衣橱里暂无可用的外套')).toBeInTheDocument()
    expect(screen.getAllByText('必选')).toHaveLength(3)
    const favorite = screen.getByRole('button', { name: '加入收藏' })
    expect(favorite).toBeDisabled()

    await userEvent.click(screen.getByRole('button', { name: '防水靴' }))
    await userEvent.click(screen.getByRole('button', { name: '白色T恤' }))
    expect(favorite).toBeDisabled()
    await userEvent.click(screen.getByRole('button', { name: '下装' }))
    expect(favorite).toBeEnabled()

    await userEvent.click(favorite)
    expect(await screen.findByText('已加入收藏')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/outfits')).toEqual([
      {
        source: 'manual',
        members: [
          { itemId: fixtureItem('白色T恤').id, slot: 'top' },
          { itemId: fixtureItem('下装').id, slot: 'bottom' },
          { itemId: fixtureItem('防水靴').id, slot: 'shoes' },
        ],
      },
    ])
    const status = calls.find((call) => call.url.pathname === '/api/v1/items')!
    expect(status.url.searchParams.get('status')).toBe('inWardrobe')
  })

  it('toggles and clears a pick', async () => {
    mockFetch({ ...routes(), '/api/v1/items': () => json({ items: available }) })
    openOutfits()
    await userEvent.click(await screen.findByRole('tab', { name: '自由拼搭' }))
    const tee = await screen.findByRole('button', { name: '白色T恤' })
    await userEvent.click(tee)
    expect(tee).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(within(screen.getByRole('region', { name: '上装' })).getByRole('button', { name: '清除' }))
    expect(tee).toHaveAttribute('aria-pressed', 'false')
    await userEvent.click(tee)
    await userEvent.click(tee)
    expect(tee).toHaveAttribute('aria-pressed', 'false')
  })
})
