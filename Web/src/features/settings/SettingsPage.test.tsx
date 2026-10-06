import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, json, mockFetch, profileFixture, requestBodies, standardRoutes } from '../../test/fixtures'

function openSettings() {
  const calls = mockFetch({
    ...standardRoutes,
    '/api/v1/settings/profile': byMethod({
      GET: () => json(profileFixture),
      PUT: (_url, init) => json(JSON.parse(String(init?.body))),
    }),
    '/api/v1/travel/plan': () => json({ days: 3, underwearCount: 4, socksCount: 4, showsCapHint: false, packingCap: 5, suggestion: [], missingRequired: [] }),
  })
  window.history.replaceState(null, '', '/settings')
  render(<App />)
  return calls
}

describe('SettingsPage', () => {
  afterEach(() => {
    document.documentElement.removeAttribute('style')
    delete document.documentElement.dataset.theme
  })

  it('edits and saves the profile', async () => {
    const calls = openSettings()
    const form = await screen.findByRole('form', { name: '个人资料' })
    expect(within(form).getByLabelText('性别')).toHaveValue('unspecified')
    const height = within(form).getByLabelText('身高（cm）')
    await userEvent.clear(height)
    await userEvent.type(height, '172.5')
    await userEvent.selectOptions(within(form).getByLabelText('性别'), 'female')
    await userEvent.click(within(form).getByRole('button', { name: '保存' }))
    expect(await screen.findByText('已保存')).toBeInTheDocument()
    expect(requestBodies(calls, 'PUT', '/api/v1/settings/profile')).toEqual([{ heightCm: 172.5, weightKg: 0, age: 0, gender: 'female' }])
  })

  it('applies and remembers appearance choices in this browser', async () => {
    openSettings()
    await userEvent.click(await screen.findByRole('radio', { name: '蓝色' }))
    expect(document.documentElement.style.getPropertyValue('--accent')).toBe('#007AFF')
    expect(window.localStorage.getItem('ui.accent')).toBe('blue')

    await userEvent.selectOptions(screen.getByLabelText('外观模式'), 'dark')
    expect(document.documentElement.dataset.theme).toBe('dark')
    expect(window.localStorage.getItem('ui.appearance')).toBe('dark')
    await userEvent.selectOptions(screen.getByLabelText('外观模式'), 'system')
    expect(document.documentElement.dataset.theme).toBeUndefined()
  })

  it('links to the travel packer and keeps 设置 highlighted', async () => {
    openSettings()
    await userEvent.click(await screen.findByRole('link', { name: '差旅打包' }))
    expect(await screen.findByRole('heading', { name: '差旅打包' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '设置' })).toHaveClass('active')
  })
})
