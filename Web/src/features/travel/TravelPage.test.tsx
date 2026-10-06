import { fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import {
  byMethod,
  fixtureItem,
  json,
  mockFetch,
  requestBodies,
  standardRoutes,
  travel10Fixture,
  travel3Fixture,
} from '../../test/fixtures'

const boots = fixtureItem('防水靴')
const tee = fixtureItem('白色T恤')

function setup({ suggestion = travel3Fixture.suggestion, luggage = [boots] } = {}) {
  let packed = luggage
  const calls = mockFetch({
    ...standardRoutes,
    '/api/v1/travel/plan': (url) => {
      const plan = url.searchParams.get('days') === '10' ? travel10Fixture : travel3Fixture
      return json({ ...plan, suggestion })
    },
    '/api/v1/items': (url) => json({ items: url.searchParams.get('status') === 'inLuggage' ? packed : [] }),
    '/api/v1/travel/pack': byMethod({ POST: () => json({ items: suggestion }) }),
    '/api/v1/travel/unpack-all': byMethod({
      POST: () => {
        const count = packed.length
        packed = []
        return json({ count })
      },
    }),
  })
  window.history.replaceState(null, '', '/travel')
  render(<App />)
  return calls
}

describe('TravelPage', () => {
  it('shows the essentials computed by the server for the trip length', async () => {
    const calls = setup()
    const essentials = await screen.findByTestId('essentials')
    expect(await within(essentials).findByText('内裤 / 打底：4 条')).toBeInTheDocument()
    expect(within(essentials).getByText('袜子：4 双')).toBeInTheDocument()
    expect(within(essentials).getByText('规则：每天 1 条 + 1 条备用。')).toBeInTheDocument()
    const request = calls.find((call) => call.url.pathname === '/api/v1/travel/plan')!
    expect(Object.fromEntries(request.url.searchParams)).toEqual({ days: '3', warmth: 'mild', scenario: 'casual' })

    fireEvent.change(screen.getByLabelText('旅行天数：3 天'), { target: { value: '10' } })
    expect(await within(essentials).findByText('内裤 / 打底：5 条')).toBeInTheDocument()
    expect(within(essentials).getByText('预计长途旅行有洗衣条件，内裤携带已封顶 5 条。')).toBeInTheDocument()
  })

  it('tells the user when there is nothing to pack', async () => {
    setup({ suggestion: [] })
    await userEvent.click(await screen.findByRole('button', { name: '按行程生成打包建议' }))
    expect(await screen.findByText('可用单品不足，换个条件试试')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /一键装入行李箱/ })).not.toBeInTheDocument()
  })

  it('packs the suggestion and ends the trip', async () => {
    const calls = setup({ suggestion: [tee] })
    expect(await screen.findByText('行李箱（1 件）')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '按行程生成打包建议' }))
    await userEvent.click(await screen.findByRole('button', { name: '一键装入行李箱（1 件）' }))
    expect(await screen.findByText('已装入行李箱')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/travel/pack')).toEqual([{ itemIds: [tee.id] }])

    await userEvent.click(screen.getByRole('button', { name: '结束差旅，全部取出' }))
    expect(await screen.findByText('已结束差旅，全部取出')).toBeInTheDocument()
    expect(screen.queryByText(/行李箱（/)).not.toBeInTheDocument()
  })
})
