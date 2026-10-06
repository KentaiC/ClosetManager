import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, json, mockFetch, noContent, standardRoutes, wearRecordsFixture } from '../../test/fixtures'

function openCalendar() {
  window.history.replaceState(null, '', '/calendar')
  render(<App />)
}

describe('CalendarPage', () => {
  it('lists records newest first and marks the active one', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/wear-records': () => json({ items: wearRecordsFixture }) })
    openCalendar()
    const records = await screen.findAllByTestId('wear-record')
    expect(records).toHaveLength(2)
    expect(within(records[0]!).getByText('正在穿')).toBeInTheDocument()
    expect(within(records[1]!).queryByText('正在穿')).not.toBeInTheDocument()
    expect(within(records[1]!).getAllByTitle(/白色T恤|下装|防水靴/)).toHaveLength(3)
  })

  it('deletes a record after confirmation', async () => {
    let records = wearRecordsFixture
    const target = wearRecordsFixture[1]!
    const calls = mockFetch({
      ...standardRoutes,
      '/api/v1/wear-records': () => json({ items: records }),
      [`/api/v1/wear-records/${target.id}`]: byMethod({
        DELETE: () => {
          records = records.filter((record) => record.id !== target.id)
          return noContent()
        },
      }),
    })
    openCalendar()
    const rows = await screen.findAllByTestId('wear-record')
    await userEvent.click(within(rows[1]!).getByRole('button', { name: '删除' }))
    const dialog = screen.getByRole('dialog', { name: '删除这条穿着记录？' })
    expect(within(dialog).getByText('删除后无法恢复。单品本身不受影响。')).toBeInTheDocument()
    await userEvent.click(within(dialog).getByRole('button', { name: '删除' }))
    expect(calls.filter((call) => call.init?.method === 'DELETE')).toHaveLength(1)
    await waitFor(() => expect(screen.getAllByTestId('wear-record')).toHaveLength(1))
  })

  it('cancels a delete without a request', async () => {
    const calls = mockFetch({ ...standardRoutes, '/api/v1/wear-records': () => json({ items: wearRecordsFixture }) })
    openCalendar()
    const rows = await screen.findAllByTestId('wear-record')
    await userEvent.click(within(rows[0]!).getByRole('button', { name: '删除' }))
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: '取消' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
    expect(calls.some((call) => call.init?.method === 'DELETE')).toBe(false)
  })

  it('shows the empty state', async () => {
    mockFetch({ ...standardRoutes, '/api/v1/wear-records': () => json({ items: [] }) })
    openCalendar()
    expect(await screen.findByText('还没有穿搭记录')).toBeInTheDocument()
  })
})
