import { fireEvent, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, fixtureItem, json, mockFetch, noContent, requestBodies, standardRoutes } from '../../test/fixtures'
import { draftFromItem, hexToColor } from './ItemEditor'

const tee = fixtureItem('白色T恤')
const bottom = fixtureItem('下装')

describe('item draft helpers', () => {
  it('starts from the stored item like ItemDraftModel(editing:)', () => {
    expect(draftFromItem(tee)).toMatchObject({ name: '白色T恤', subtype: 'tee', seasonsManuallyEdited: true, colorHex: '#F5F5F5', colorChanged: false })
    expect(draftFromItem(bottom)).toMatchObject({ name: '', seasons: [], seasonsManuallyEdited: false, brand: '', notes: '' })
  })

  it('converts #RRGGBB to sRGB components', () => {
    expect(hexToColor('#FF8000')).toEqual({ red: 1, green: 128 / 255, blue: 0, alpha: 1 })
  })
})

function openItem(item = tee, put = (body: unknown) => json({ ...item, ...(body as object) })) {
  const calls = mockFetch({
    ...standardRoutes,
    [`/api/v1/items/${item.id}`]: byMethod({
      GET: () => json(item),
      PUT: (_url, init) => put(JSON.parse(String(init?.body))),
      DELETE: noContent,
    }),
    '/api/v1/naming/default-name': () => json({ name: '藏青牛仔裤' }),
  })
  window.history.replaceState(null, '', `/items/${item.id}`)
  render(<App />)
  return calls
}

describe('editing an item', () => {
  it('submits every field and keeps the stored colour components when the colour is unchanged', async () => {
    const calls = openItem()
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    const form = screen.getByRole('form', { name: '编辑单品' })
    const brand = within(form).getByLabelText('品牌')
    await userEvent.clear(brand)
    await userEvent.type(brand, '新品牌')
    await userEvent.click(within(form).getByRole('button', { name: '保存' }))
    expect(await screen.findByText('已保存')).toBeInTheDocument()
    expect(requestBodies(calls, 'PUT', `/api/v1/items/${tee.id}`)).toEqual([
      {
        name: '白色T恤',
        category: 'top',
        subtype: 'tee',
        scenarios: ['work', 'casual'],
        warmthScore: 20,
        seasons: ['spring', 'summer'],
        status: 'inWardrobe',
        isWaterproof: false,
        brand: '新品牌',
        notes: '',
        dominantColor: { red: 0.96, green: 0.96, blue: 0.96, alpha: 1 },
      },
    ])
    expect(screen.getByRole('heading', { name: '白色T恤' })).toBeInTheDocument()
  })

  it('shows the server default name for an unnamed item and derives seasons from warmth', async () => {
    const calls = openItem(bottom)
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    const form = screen.getByRole('form', { name: '编辑单品' })
    expect(await within(form).findByPlaceholderText('藏青牛仔裤')).toBeInTheDocument()
    expect(within(form).getByText('名称已按「颜色 + 子类」自动生成，可直接修改。')).toBeInTheDocument()
    const request = calls.find((call) => call.url.pathname === '/api/v1/naming/default-name')!
    expect(Object.fromEntries(request.url.searchParams)).toEqual({ category: 'bottom', subtype: 'jeans', color: '1F294F' })

    fireEvent.change(within(form).getByRole('slider'), { target: { value: '90' } })
    expect(within(form).getByText('保暖度 90（严寒）')).toBeInTheDocument()
    const seasons = within(form).getByRole('group', { name: '适用季节' })
    expect(within(seasons).getByRole('button', { name: '冬' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(seasons).getByRole('button', { name: '秋' })).toHaveAttribute('aria-pressed', 'false')

    // 手动调整季节后不再随保暖度变化，直到恢复自动匹配。
    await userEvent.click(within(seasons).getByRole('button', { name: '春' }))
    fireEvent.change(within(form).getByRole('slider'), { target: { value: '20' } })
    expect(within(seasons).getByRole('button', { name: '冬' })).toHaveAttribute('aria-pressed', 'true')
    await userEvent.click(within(form).getByRole('button', { name: '恢复为按保暖程度自动匹配' }))
    expect(within(seasons).getByRole('button', { name: '夏' })).toHaveAttribute('aria-pressed', 'true')
    expect(within(seasons).getByRole('button', { name: '冬' })).toHaveAttribute('aria-pressed', 'false')
  })

  it('clears a subtype that does not belong to the new category and warns about conflicting scenarios', async () => {
    openItem()
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    const form = screen.getByRole('form', { name: '编辑单品' })
    await userEvent.selectOptions(within(form).getByLabelText('分类'), 'bottom')
    expect(within(form).getByLabelText('子类')).toHaveValue('')
    const scenarios = within(form).getByRole('group', { name: '适用场景' })
    await userEvent.click(within(scenarios).getByRole('button', { name: '正式' }))
    await userEvent.click(within(scenarios).getByRole('button', { name: '运动' }))
    expect(within(form).getByText('「正式」与「运动」相互冲突，建议不要同时选择。')).toBeInTheDocument()
  })

  it('shows a validation error from the server and stays in the editor', async () => {
    openItem(tee, () => json({ error: { code: 'invalid_request', message: '保暖度必须在 1 到 100 之间。' } }, 400))
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    await userEvent.click(screen.getByRole('button', { name: '保存' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('保暖度必须在 1 到 100 之间。')
    expect(screen.getByRole('form', { name: '编辑单品' })).toBeInTheDocument()
  })
})

describe('deleting an item', () => {
  it('asks for confirmation, deletes and returns to the wardrobe', async () => {
    const calls = openItem()
    await userEvent.click(await screen.findByRole('button', { name: '删除' }))
    const dialog = screen.getByRole('dialog', { name: '删除「白色T恤」？' })
    await userEvent.click(within(dialog).getByRole('button', { name: '删除' }))
    expect(await screen.findByRole('heading', { name: '我的衣橱' })).toBeInTheDocument()
    expect(screen.getByText('已删除')).toBeInTheDocument()
    expect(calls.some((call) => call.init?.method === 'DELETE' && call.url.pathname === `/api/v1/items/${tee.id}`)).toBe(true)
  })
})
