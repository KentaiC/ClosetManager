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
