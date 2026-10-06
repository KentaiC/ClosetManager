import { describe, expect, it } from 'vitest'
import { json, mockFetch } from '../test/fixtures'
import { ApiError, CLIENT_HEADER, api, request } from './client'

describe('request', () => {
  it('sends the client header only on writes', async () => {
    const calls = mockFetch({ '/api/v1/x': () => json({ ok: true }) })
    await request('GET', '/api/v1/x')
    await request('POST', '/api/v1/x', { a: 1 })
    const getHeaders = calls[0]!.init!.headers as Record<string, string>
    const postHeaders = calls[1]!.init!.headers as Record<string, string>
    expect(getHeaders[CLIENT_HEADER]).toBeUndefined()
    expect(postHeaders[CLIENT_HEADER]).toBe('web')
    expect(postHeaders['Content-Type']).toBe('application/json')
    expect(calls[1]!.init!.body).toBe('{"a":1}')
    expect(calls[1]!.init!.credentials).toBe('same-origin')
  })

  it('turns JSON errors into ApiError', async () => {
    mockFetch({ '/api/v1/x': () => json({ error: { code: 'invalid_parameter', message: '参数无效。' } }, 400) })
    await expect(request('GET', '/api/v1/x')).rejects.toMatchObject({ status: 400, code: 'invalid_parameter', message: '参数无效。' })
  })

  it('falls back when the error body is not JSON', async () => {
    mockFetch({ '/api/v1/x': () => new Response('boom', { status: 502 }) })
    const error = await request('GET', '/api/v1/x').catch((e: unknown) => e)
    expect(error).toBeInstanceOf(ApiError)
    expect(error).toMatchObject({ status: 502, code: 'http_502' })
  })

  it('reports network failures in Chinese', async () => {
    globalThis.fetch = (() => Promise.reject(new TypeError('Failed to fetch'))) as typeof fetch
    await expect(request('GET', '/api/v1/x')).rejects.toMatchObject({ status: 0, code: 'network_error' })
  })

  it('builds filter queries and unwraps lists', async () => {
    const calls = mockFetch({ '/api/v1/items': () => json({ items: [] }), '/api/v1/outfits': () => json({ items: [] }) })
    await api.items({ status: 'inLaundry', category: undefined })
    await api.outfits(true)
    await api.outfits(false)
    expect(calls.map((c) => c.url.search)).toEqual(['?status=inLaundry', '?favorite=true', ''])
  })
})
