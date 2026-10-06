import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import type { ApiProcessedImage } from '../../api/types'
import { byMethod, fixtureItem, itemsFixture, json, mockFetch, requestBodies, standardRoutes } from '../../test/fixtures'
import { imageFile, uploaded } from '../../test/images'

describe('BatchImportPage', () => {
  function batchRoutes(delayFirst?: Promise<void>) {
    let uploads = 0
    return {
      ...standardRoutes,
      '/api/v1/images': byMethod({
        POST: async () => {
          uploads += 1
          const sha = String(uploads).repeat(64)
          if (uploads === 1 && delayFirst) await delayFirst
          return json(uploaded(sha), 201)
        },
      }),
      '/api/v1/naming/default-name': () => json({ name: '灰色T恤' }),
      '/api/v1/items': byMethod({ GET: () => json({ items: itemsFixture }), POST: () => json(fixtureItem('白色T恤'), 201) }),
      ...Object.fromEntries(
        ['1', '2', '3'].map((n) => [`/api/v1/images/${n.repeat(64)}/process`, byMethod({ POST: () => json({ original: uploaded(n.repeat(64)) } satisfies ApiProcessedImage) })]),
      ),
    }
  }

  it('walks the queue: save, skip, finish', async () => {
    const calls = mockFetch(batchRoutes())
    window.history.replaceState(null, '', '/items/batch')
    render(<App />)
    await userEvent.upload(await screen.findByLabelText('选择多张图片'), [imageFile('a.jpg'), imageFile('b.jpg'), imageFile('c.jpg')])
    expect(await screen.findByText('第 1 / 3 件')).toBeInTheDocument()
    expect(screen.queryByLabelText('更换图片')).not.toBeInTheDocument()
    const next = screen.getByRole('button', { name: '保存并下一件' })
    await waitFor(() => expect(next).toBeEnabled())
    await userEvent.click(next)

    expect(await screen.findByText('第 2 / 3 件')).toBeInTheDocument()
    await userEvent.click(screen.getByRole('button', { name: '跳过这张' }))

    expect(await screen.findByText('第 3 / 3 件')).toBeInTheDocument()
    const finish = screen.getByRole('button', { name: '保存并完成' })
    await waitFor(() => expect(finish).toBeEnabled())
    await userEvent.click(finish)
    expect(await screen.findByRole('heading', { name: '我的衣橱' })).toBeInTheDocument()
    expect(screen.getByText('已保存 2 件')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/items').map((body) => (body as { images: { original: string } }).images.original)).toEqual([
      '1'.repeat(64),
      '3'.repeat(64),
    ])
  })

  it('ignores a slow image once the user has skipped it', async () => {
    let release: () => void = () => {}
    const slow = new Promise<void>((resolve) => (release = resolve))
    const calls = mockFetch(batchRoutes(slow))
    window.history.replaceState(null, '', '/items/batch')
    render(<App />)
    await userEvent.upload(await screen.findByLabelText('选择多张图片'), [imageFile('a.jpg'), imageFile('b.jpg')])
    await userEvent.click(await screen.findByRole('button', { name: '跳过这张' }))
    expect(await screen.findByText('第 2 / 2 件')).toBeInTheDocument()
    release()
    const finish = screen.getByRole('button', { name: '保存并完成' })
    await waitFor(() => expect(finish).toBeEnabled())
    await userEvent.click(finish)
    await screen.findByRole('heading', { name: '我的衣橱' })
    expect(calls.some((call) => call.url.pathname === `/api/v1/images/${'1'.repeat(64)}/process`)).toBe(false)
    expect(requestBodies(calls, 'POST', '/api/v1/items')).toEqual([expect.objectContaining({ images: { original: '2'.repeat(64) } })])
  })
})
