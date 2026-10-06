import type {
  ApiAnalytics,
  ApiHealth,
  ApiImportReport,
  ApiItem,
  ApiList,
  ApiMember,
  ApiMeta,
  ApiOutfit,
  ApiProcessedImage,
  ApiProfile,
  ApiSuggestions,
  ApiTravelPlan,
  ApiUploadedImage,
  ApiWearRecord,
  ItemUpdate,
} from './types'

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

/** 发送请求并在失败时抛出 ApiError。body 为 Blob 时按原始字节发送（上传图片与备份文件）。 */
async function send(method: Method, path: string, body?: unknown): Promise<Response> {
  const headers: Record<string, string> = { Accept: 'application/json' }
  if (method !== 'GET') headers[CLIENT_HEADER] = 'web'
  let payload: BodyInit | undefined
  if (body instanceof Blob) {
    headers['Content-Type'] = body.type || 'application/octet-stream'
    payload = body
  } else if (body !== undefined) {
    headers['Content-Type'] = 'application/json'
    payload = JSON.stringify(body)
  }
  let response: Response
  try {
    response = await fetch(path, { method, headers, body: payload, credentials: 'same-origin' })
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
  return response
}

export async function request<T>(method: Method, path: string, body?: unknown): Promise<T> {
  const response = await send(method, path, body)
  if (response.status === 204) return undefined as T
  return (await response.json()) as T
}

/** 从 Content-Disposition 中取出文件名。 */
export function fileNameFrom(disposition: string | null, fallback: string): string {
  const match = disposition ? /filename="([^"]+)"/.exec(disposition) : null
  return match?.[1] ?? fallback
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
  items: (filter: { status?: string; category?: string; sort?: 'createdAt' | 'updatedAt' } = {}) =>
    request<ApiList<ApiItem>>('GET', `/api/v1/items${query(filter)}`).then((list) => list.items),
  item: (id: string) => request<ApiItem>('GET', `/api/v1/items/${encodeURIComponent(id)}`),
  createItem: (item: ItemUpdate) => request<ApiItem>('POST', '/api/v1/items', item),
  updateItem: (id: string, update: ItemUpdate) => request<ApiItem>('PUT', `/api/v1/items/${encodeURIComponent(id)}`, update),
  deleteItem: (id: string) => request<void>('DELETE', `/api/v1/items/${encodeURIComponent(id)}`),
  defaultName: (category: string, subtype: string | null, colorHex: string) =>
    request<{ name: string }>(
      'GET',
      `/api/v1/naming/default-name${query({ category, subtype: subtype ?? undefined, color: colorHex.replace('#', '') })}`,
    ).then((result) => result.name),

  outfits: (favoritesOnly: boolean) =>
    request<ApiList<ApiOutfit>>('GET', `/api/v1/outfits${query({ favorite: favoritesOnly ? 'true' : undefined })}`).then(
      (list) => list.items,
    ),
  suggestions: (params: { warmth: string; scenario: string; requireWaterproof: boolean; maxCount?: number }) =>
    request<ApiSuggestions>(
      'GET',
      `/api/v1/outfit-suggestions${query({
        warmth: params.warmth,
        scenario: params.scenario,
        requireWaterproof: String(params.requireWaterproof),
        maxCount: params.maxCount?.toString(),
      })}`,
    ),
  createOutfit: (body: {
    source: 'generated' | 'manual'
    targetScenario?: string
    targetWarmthLevel?: string
    members: ApiMember[]
  }) => request<ApiOutfit>('POST', '/api/v1/outfits', body),
  wearOutfit: (id: string) => request<ApiWearRecord>('POST', `/api/v1/outfits/${encodeURIComponent(id)}/wear`),
  deleteOutfit: (id: string) => request<void>('DELETE', `/api/v1/outfits/${encodeURIComponent(id)}`),

  wearRecords: () => request<ApiList<ApiWearRecord>>('GET', '/api/v1/wear-records').then((list) => list.items),
  activeWearRecord: () =>
    request<{ record?: ApiWearRecord }>('GET', '/api/v1/wear-records/active').then((result) => result.record ?? null),
  wear: (members: ApiMember[]) => request<ApiWearRecord>('POST', '/api/v1/wear-records', { members }),
  takeOff: (recordId: string, laundryItemIds: string[]) =>
    request<ApiWearRecord>('POST', `/api/v1/wear-records/${encodeURIComponent(recordId)}/take-off`, { laundryItemIds }),
  deleteWearRecord: (id: string) => request<void>('DELETE', `/api/v1/wear-records/${encodeURIComponent(id)}`),
  returnFromLaundry: (itemIds: string[]) =>
    request<ApiList<ApiItem>>('POST', '/api/v1/laundry/return', { itemIds }).then((list) => list.items),

  analytics: () => request<ApiAnalytics>('GET', '/api/v1/analytics'),
  search: (params: { scenario?: string; colorCategory?: string; waterproof?: boolean; unwornDays?: number }) =>
    request<ApiList<ApiItem>>(
      'GET',
      `/api/v1/search${query({
        scenario: params.scenario,
        colorCategory: params.colorCategory,
        waterproof: params.waterproof ? 'true' : undefined,
        unwornDays: params.unwornDays?.toString(),
      })}`,
    ).then((list) => list.items),

  travelPlan: (params: { days: number; warmth: string; scenario: string }) =>
    request<ApiTravelPlan>('GET', `/api/v1/travel/plan${query({ ...params, days: String(params.days) })}`),
  pack: (itemIds: string[]) => request<ApiList<ApiItem>>('POST', '/api/v1/travel/pack', { itemIds }).then((list) => list.items),
  unpackAll: () => request<{ count: number }>('POST', '/api/v1/travel/unpack-all').then((result) => result.count),

  uploadImage: (file: Blob) => request<ApiUploadedImage>('POST', '/api/v1/images', file),
  processImage: (sha256: string) => request<ApiProcessedImage>('POST', `/api/v1/images/${encodeURIComponent(sha256)}/process`),
  similarItems: () => request<{ groups: ApiItem[][] }>('GET', '/api/v1/similar-items').then((result) => result.groups),

  exportBackup: async () => {
    const response = await send('POST', '/api/v1/backup/export')
    return { blob: await response.blob(), fileName: fileNameFrom(response.headers.get('Content-Disposition'), 'ClosetBackup.wardrobe') }
  },
  importBackup: (file: Blob, mode: 'merge' | 'overwrite', apply: boolean) =>
    request<ApiImportReport>('POST', `/api/v1/backup/import${query({ mode, apply: String(apply) })}`, file),

  profile: () => request<ApiProfile>('GET', '/api/v1/settings/profile'),
  updateProfile: (profile: ApiProfile) => request<ApiProfile>('PUT', '/api/v1/settings/profile', profile),
}
