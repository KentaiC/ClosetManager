import { render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from './App'
import { mockFetch, standardRoutes } from './test/fixtures'

describe('App shell', () => {
  it('explains how to recover when the local server is not running', async () => {
    globalThis.fetch = (() => Promise.reject(new TypeError('Failed to fetch'))) as typeof fetch
    render(<App />)
    expect(await screen.findByRole('alert')).toHaveTextContent('无法连接到本地服务，请确认 closet-server 正在运行。')
    mockFetch(standardRoutes)
    await userEvent.click(screen.getByRole('button', { name: '重试' }))
    expect(await screen.findByRole('heading', { name: '我的衣橱' })).toBeInTheDocument()
  })

  it('navigates between the five tabs and marks the current one', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    await screen.findByRole('heading', { name: '我的衣橱' })
    const nav = screen.getByRole('navigation', { name: '主导航' })
    expect(Array.from(nav.querySelectorAll('a')).map((a) => a.textContent)).toEqual(['衣橱', '洗衣房', '穿搭', '日历', '看板'])
    await userEvent.click(screen.getByRole('link', { name: '洗衣房' }))
    expect(await screen.findByRole('heading', { name: '洗衣房' })).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '洗衣房' })).toHaveAttribute('aria-current', 'page')
  })

  it('shows a not-found item page with a way back', async () => {
    window.history.replaceState(null, '', '/items/00000000-0000-0000-0000-000000000000')
    mockFetch(standardRoutes)
    render(<App />)
    expect(await screen.findByText('未找到该单品')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '返回衣橱' })).toHaveAttribute('href', '/')
  })

  it('shows a not-found page for unknown addresses', async () => {
    window.history.replaceState(null, '', '/nowhere')
    mockFetch(standardRoutes)
    render(<App />)
    expect(await screen.findByRole('heading', { name: '页面不存在' })).toBeInTheDocument()
    expect(screen.getByText('没有找到这个页面')).toBeInTheDocument()
    expect(screen.getByRole('link', { name: '返回衣橱' })).toHaveAttribute('href', '/')
  })
})
