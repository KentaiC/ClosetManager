// 测试样例来自真实运行的 closet-server（导入 Tests/Fixtures/wardrobe-v1-sample.wardrobe 后抓取）。
import type { ApiItem, ApiMeta, ApiOutfit, ApiWearRecord } from '../api/types'
import itemsJSON from './fixtures/items.json'
import metaJSON from './fixtures/meta.json'
import outfitsJSON from './fixtures/outfits.json'
import activeJSON from './fixtures/wear-records-active.json'

export const metaFixture = metaJSON as ApiMeta
export const itemsFixture = (itemsJSON as { items: ApiItem[] }).items
export const outfitsFixture = (outfitsJSON as { items: ApiOutfit[] }).items
export const activeFixture = (activeJSON as { record: ApiWearRecord }).record

type Handler = (url: URL, init: RequestInit | undefined) => Response | Promise<Response>

export function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
}

/** 按路径替换 fetch；未登记的路径返回 404 JSON。返回记录下来的请求。 */
export function mockFetch(routes: Record<string, Handler>) {
  const calls: { url: URL; init: RequestInit | undefined }[] = []
  const fetchMock = async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url, 'http://127.0.0.1:8765')
    calls.push({ url, init })
    const handler = routes[url.pathname]
    if (!handler) return json({ error: { code: 'not_found', message: '未找到请求的资源。' } }, 404)
    return handler(url, init)
  }
  globalThis.fetch = fetchMock as typeof fetch
  return calls
}

export const standardRoutes: Record<string, Handler> = {
  '/api/v1/meta': () => json(metaFixture),
  '/api/v1/items': () => json({ items: itemsFixture }),
  '/api/v1/wear-records/active': () => json({ record: activeFixture }),
}
