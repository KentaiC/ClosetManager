import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, fixtureItem, json, mockFetch, requestBodies, standardRoutes, wearRecordsFixture } from '../../test/fixtures'

// 用含上装、下装、鞋子三件的记录作为当前穿搭。
const record = { ...wearRecordsFixture[1]!, isActive: true }
const takeOffPath = `/api/v1/wear-records/${record.id}/take-off`

function setup(takeOff = () => json({ ...record, isActive: false })) {
  let active: unknown = record
  const calls = mockFetch({
    ...standardRoutes,
    '/api/v1/wear-records/active': () => json(active ? { record: active } : {}),
    [takeOffPath]: byMethod({
      POST: () => {
        const response = takeOff()
        if (response.ok) active = null
        return response
      },
    }),
  })
  render(<App />)
  return calls
}

async function openDialog() {
  await userEvent.click(await screen.findByRole('button', { name: '脱下并扔进洗衣袋' }))
  return screen.getByRole('dialog', { name: '脱下穿搭' })
}

describe('TakeOffDialog', () => {
  it('pre-checks top, bottom and socks like the App', async () => {
    setup()
    const dialog = await openDialog()
    const boxes = within(dialog).getAllByRole('checkbox')
    expect(boxes.map((box) => (box as HTMLInputElement).checked)).toEqual([true, true, false])
  })

  it('takes off only the checked items and refreshes the active outfit', async () => {
    const calls = setup()
    const dialog = await openDialog()
    await userEvent.click(within(dialog).getByRole('button', { name: '按勾选脱下' }))
    expect(await screen.findByText('今天尚未选择穿搭')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', takeOffPath)).toEqual([
      { laundryItemIds: [fixtureItem('白色T恤').id, fixtureItem('下装').id] },
    ])
  })

  it('puts everything in the laundry with one tap', async () => {
    const calls = setup()
    const dialog = await openDialog()
    await userEvent.click(within(dialog).getAllByRole('checkbox')[0]!)
    await userEvent.click(within(dialog).getByRole('button', { name: '一键全扔进洗衣袋' }))
    expect(await screen.findByText('今天尚未选择穿搭')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', takeOffPath)).toEqual([{ laundryItemIds: record.items.map((item) => item.id) }])
  })

  it('keeps the dialog open and shows the server message on failure', async () => {
    setup(() => json({ error: { code: 'conflict', message: '这条记录已经不在穿着中。' } }, 409))
    const dialog = await openDialog()
    await userEvent.click(within(dialog).getByRole('button', { name: '按勾选脱下' }))
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('这条记录已经不在穿着中。')
  })

  it('closes with Escape without a request', async () => {
    const calls = setup()
    await openDialog()
    await userEvent.keyboard('{Escape}')
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(requestBodies(calls, 'POST', takeOffPath)).toEqual([])
  })
})
