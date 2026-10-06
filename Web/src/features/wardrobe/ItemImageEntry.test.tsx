import { render, screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { App } from '../../App'
import { byMethod, fixtureItem, itemsFixture, json, macHealthFixture, mockFetch, requestBodies, standardRoutes } from '../../test/fixtures'
import { CUTOUT_SHA, imageFile, linuxProcessed, macProcessed, ORIGINAL_SHA } from '../../test/images'
import { applyIngest, newDraft, updateFromDraft } from './ItemEditor'

const tee = fixtureItem('白色T恤')
const bottom = fixtureItem('下装')

describe('draft helpers', () => {
  it('starts a new item like ItemDraftModel()', () => {
    expect(updateFromDraft(newDraft())).toEqual({
      name: '',
      category: 'top',
      subtype: null,
      scenarios: [],
      warmthScore: 50,
      seasons: [],
      status: 'inWardrobe',
      isWaterproof: false,
      brand: '',
      notes: '',
      dominantColor: { red: 0.5, green: 0.5, blue: 0.5, alpha: 1 },
    })
  })

  it('takes images and colours from processing and keeps the colour when none was extracted', () => {
    const mac = updateFromDraft(applyIngest(newDraft(), macProcessed))
    expect(mac.images).toEqual({ original: ORIGINAL_SHA, processed: CUTOUT_SHA, secondaryColor: { red: 0.9, green: 0.9, blue: 0.9, alpha: 1 } })
    expect(mac.dominantColor).toEqual({ red: 0.1, green: 0.2, blue: 0.7, alpha: 1 })

    const linux = updateFromDraft(applyIngest(newDraft(), linuxProcessed))
    expect(linux.images).toEqual({ original: ORIGINAL_SHA })
    expect(linux.dominantColor).toEqual({ red: 0.5, green: 0.5, blue: 0.5, alpha: 1 })
  })
})

function routes(processed = linuxProcessed, extra: Record<string, Parameters<typeof mockFetch>[0][string]> = {}) {
  return {
    ...standardRoutes,
    '/api/v1/images': byMethod({ POST: () => json(processed.original, 201) }),
    [`/api/v1/images/${ORIGINAL_SHA}/process`]: byMethod({ POST: () => json(processed) }),
    '/api/v1/items': byMethod({ GET: () => json({ items: itemsFixture }), POST: () => json(tee, 201) }),
    '/api/v1/naming/default-name': () => json({ name: '灰色T恤' }),
    ...extra,
  }
}

describe('adding a single item', () => {
  it('uploads, uses the original on Linux, asks for a manual colour and saves', async () => {
    const calls = mockFetch(routes())
    window.history.replaceState(null, '', '/items/new')
    render(<App />)
    const form = await screen.findByRole('form', { name: '新增单品' })
    expect(within(form).getByText('尚未选择图片')).toBeInTheDocument()
    expect(within(form).getByRole('button', { name: '保存' })).toBeDisabled()
    expect(within(form).getByText('请先添加图片。')).toBeInTheDocument()

    await userEvent.upload(within(form).getByLabelText('添加图片'), imageFile())
    expect(await within(form).findByRole('img', { name: '图片预览' })).toHaveAttribute('src', `/api/v1/images/${ORIGINAL_SHA}`)
    expect(within(form).getByText('当前服务不支持本地抠图，已使用原图。')).toBeInTheDocument()
    expect(within(form).getByText('当前服务不支持自动取色，请在下方手动选择主色。')).toBeInTheDocument()
    expect(within(form).getByRole('button', { name: '更换图片' })).toBeEnabled()

    const upload = calls.find((call) => call.url.pathname === '/api/v1/images')!
    expect(upload.init?.body).toBeInstanceOf(Blob)
    expect((upload.init?.headers as Record<string, string>)['X-Closet-Client']).toBe('web')
    expect((upload.init?.headers as Record<string, string>)['Content-Type']).toBe('image/jpeg')

    await userEvent.click(within(form).getByRole('button', { name: '保存' }))
    expect(await screen.findByRole('heading', { name: '我的衣橱' })).toBeInTheDocument()
    expect(screen.getByText('已添加')).toBeInTheDocument()
    expect(requestBodies(calls, 'POST', '/api/v1/items')).toEqual([
      expect.objectContaining({ category: 'top', images: { original: ORIGINAL_SHA }, dominantColor: { red: 0.5, green: 0.5, blue: 0.5, alpha: 1 } }),
    ])
  })

  it('shows the cutout and extracted colours on macOS', async () => {
    const calls = mockFetch({ ...routes(macProcessed), '/api/v1/health': () => json(macHealthFixture) })
    window.history.replaceState(null, '', '/items/new')
    render(<App />)
    const form = await screen.findByRole('form', { name: '新增单品' })
    await userEvent.upload(within(form).getByLabelText('添加图片'), imageFile())
    expect(await within(form).findByRole('img', { name: '图片预览' })).toHaveAttribute('src', `/api/v1/images/${CUTOUT_SHA}`)
    expect(within(form).queryByText(/不支持/)).not.toBeInTheDocument()
    expect(within(form).getByLabelText('主色')).toHaveValue('#1a33b3')
    await userEvent.click(within(form).getByRole('button', { name: '保存' }))
    await screen.findByRole('heading', { name: '我的衣橱' })
    expect(requestBodies(calls, 'POST', '/api/v1/items')).toEqual([
      expect.objectContaining({
        images: { original: ORIGINAL_SHA, processed: CUTOUT_SHA, secondaryColor: { red: 0.9, green: 0.9, blue: 0.9, alpha: 1 } },
        dominantColor: { red: 0.1, green: 0.2, blue: 0.7, alpha: 1 },
      }),
    ])
  })

  it('shows the App failure message and still allows saving', async () => {
    const failed = { ...linuxProcessed, dominantColor: macProcessed.dominantColor, failure: '未能识别到衣物主体，请换一张主体清晰、背景简单的图片。' }
    mockFetch({ ...routes(failed), '/api/v1/health': () => json(macHealthFixture) })
    window.history.replaceState(null, '', '/items/new')
    render(<App />)
    const form = await screen.findByRole('form', { name: '新增单品' })
    await userEvent.upload(within(form).getByLabelText('添加图片'), imageFile())
    expect(await within(form).findByText('未能识别到衣物主体，请换一张主体清晰、背景简单的图片。')).toBeInTheDocument()
    expect(within(form).getByRole('button', { name: '保存' })).toBeEnabled()
  })

  it('reports a rejected upload', async () => {
    mockFetch(routes(linuxProcessed, {
      '/api/v1/images': byMethod({
        POST: () => json({ error: { code: 'invalid_request', message: '不支持的文件类型。只接受 JPEG、PNG、HEIC、HEIF 与 WebP 图片。' } }, 400),
      }),
    }))
    window.history.replaceState(null, '', '/items/new')
    render(<App />)
    const form = await screen.findByRole('form', { name: '新增单品' })
    await userEvent.upload(within(form).getByLabelText('添加图片'), imageFile('photo.webp', 'image/webp'))
    expect(await within(form).findByRole('alert')).toHaveTextContent('不支持的文件类型')
    expect(within(form).getByRole('button', { name: '保存' })).toBeDisabled()
  })
})

describe('editing images', () => {
  it('replaces the image of an existing item', async () => {
    const calls = mockFetch(routes(macProcessed, {
      '/api/v1/health': () => json(macHealthFixture),
      [`/api/v1/items/${tee.id}`]: byMethod({ GET: () => json(tee), PUT: (_url, init) => json({ ...tee, ...JSON.parse(String(init?.body)) }) }),
    }))
    window.history.replaceState(null, '', `/items/${tee.id}`)
    render(<App />)
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    const form = screen.getByRole('form', { name: '编辑单品' })
    expect(within(form).getByRole('img', { name: '白色T恤' })).toHaveAttribute('src', tee.images.display!.url)
    await userEvent.upload(within(form).getByLabelText('更换图片'), imageFile())
    await within(form).findByRole('img', { name: '图片预览' })
    await userEvent.click(within(form).getByRole('button', { name: '保存' }))
    await screen.findByText('已保存')
    expect(requestBodies(calls, 'PUT', `/api/v1/items/${tee.id}`)).toEqual([
      expect.objectContaining({ images: expect.objectContaining({ original: ORIGINAL_SHA, processed: CUTOUT_SHA }) }),
    ])
  })

  it('cannot save an item without any image, like the App', async () => {
    mockFetch(routes(linuxProcessed, { [`/api/v1/items/${bottom.id}`]: () => json(bottom) }))
    window.history.replaceState(null, '', `/items/${bottom.id}`)
    render(<App />)
    await userEvent.click(await screen.findByRole('button', { name: '编辑' }))
    const form = screen.getByRole('form', { name: '编辑单品' })
    expect(within(form).getByRole('button', { name: '保存' })).toBeDisabled()
    await userEvent.upload(within(form).getByLabelText('添加图片'), imageFile())
    await waitFor(() => expect(within(form).getByRole('button', { name: '保存' })).toBeEnabled())
  })
})

describe('gallery thumbnails', () => {
  it('lists items with their thumbnail address', async () => {
    mockFetch(standardRoutes)
    render(<App />)
    const card = await screen.findByRole('link', { name: '白色T恤' })
    expect(within(card).getByRole('img')).toHaveAttribute('src', tee.images.thumbnailUrl)
  })
})

