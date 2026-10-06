import type { ApiHealth, ApiItem, ApiList, ApiMeta, ApiOutfit, ApiWearRecord } from './types'

/** 服务端返回的错误，或网络错误。 */
export class ApiError extends Error {
  readonly status: number
  readonly code: string

  constructor(status: number, code: string, message: string) {
    super(message)
    this.name = 'ApiError'
    this.status = status
    this.code = code
  }
}

/** 写请求必须携带的头，服务端据此拒绝跨站伪造的请求。 */
export const CLIENT_HEADER = 'X-Closet-Client'

type Method = 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE'

export async function request<T>(method: Method, path: string, body?: unknown): Promise<T> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (method !== 'GET') headers[CLIENT_HEADER] = 'web'
  if (body !== undefined) headers['Content-Type'] = 'application/json'
  let response: Response
  try {
    response = await fetch(path, {
      method,
      headers,
      body: body === undefined ? undefined : JSON.stringify(body),
      credentials: 'same-origin',
    })
  } catch {
    throw new ApiError(0, 'network_error', '无法连接到本地服务，请确认 closet-server 正在运行。')
  }
  if (!response.ok) {
    let code = `http_${response.status}`
    let message = `请求失败（HTTP ${response.status}）。`
    try {
      const payload = (await response.json()) as { error?: { code?: string; message?: string } }
      if (payload.error?.code) code = payload.error.code
      if (payload.error?.message) message = payload.error.message
    } catch {
      // 响应不是 JSON，保留默认文案。
    }
    throw new ApiError(response.status, code, message)
  }
  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

function query(params: Record<string, string | undefined>): string {
  const search = new URLSearchParams()
  for (const [key, value] of Object.entries(params)) {
    if (value !== undefined && value !== '') search.set(key, value)
  }
  const text = search.toString()
  return text ? `?${text}` : ''
}

export const api = {
  health: () => request<ApiHealth>('GET', '/api/v1/health'),
  meta: () => request<ApiMeta>('GET', '/api/v1/meta'),
  items: (filter: { status?: string; category?: string } = {}) =>
    request<ApiList<ApiItem>>('GET', `/api/v1/items${query(filter)}`).then((list) => list.items),
  item: (id: string) => request<ApiItem>('GET', `/api/v1/items/${encodeURIComponent(id)}`),
  outfits: (favoritesOnly: boolean) =>
    request<ApiList<ApiOutfit>>('GET', `/api/v1/outfits${query({ favorite: favoritesOnly ? 'true' : undefined })}`).then(
      (list) => list.items,
    ),
  wearRecords: () => request<ApiList<ApiWearRecord>>('GET', '/api/v1/wear-records').then((list) => list.items),
  activeWearRecord: () =>
    request<{ record?: ApiWearRecord }>('GET', '/api/v1/wear-records/active').then((result) => result.record ?? null),
}
