import { expect, type Page } from '@playwright/test'

/** 收集页面上的脚本错误与控制台错误（包括 CSP 拦截），测试结束时断言为空。 */
export function trackPageErrors(page: Page): () => void {
  const errors: string[] = []
  page.on('pageerror', (error) => errors.push(`pageerror: ${error.message}`))
  page.on('console', (message) => {
    if (message.type() === 'error') errors.push(`console: ${message.text()}`)
  })
  return () => expect(errors, errors.join('\n')).toEqual([])
}

export const TEE_ID = '7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E'
export const BOTTOM_ID = '8B3D2E0F-4C5A-4D6B-8E7F-2A3B4C5D6E7F'
export const BOOTS_ID = '9C4E3F1A-5D6B-4E7C-9F8A-3B4C5D6E7F8A'

/** 1×1 PNG，与 Tests/Fixtures 样例备份中的图片相同。 */
export const TINY_PNG = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==', 'base64')

export function photo(name: string) {
  return { name, mimeType: 'image/png', buffer: TINY_PNG }
}
