import { expect, test } from '@playwright/test'
import { TEE_ID, trackPageErrors } from './support'

// 手机宽度下的布局检查，只读取数据：每个页面都不出现横向滚动，底部标签栏可以切换页面。
test.use({ viewport: { width: 390, height: 844 } })

const pages = ['/', '/laundry', '/outfits', '/calendar', '/analytics', '/settings', '/search', '/travel', '/items/new', '/items/batch', '/similar', `/items/${TEE_ID}`]

test('no page scrolls sideways on a phone', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  for (const path of pages) {
    await page.goto(path)
    await expect(page.getByRole('heading', { level: 1 })).toBeVisible()
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
    expect(overflow, path).toBeLessThanOrEqual(0)
  }
  assertNoErrors()
})

test('the bottom tab bar switches pages and stays above the content', async ({ page }) => {
  await page.goto('/')
  const nav = page.getByRole('navigation', { name: '主导航' })
  const box = await nav.boundingBox()
  expect(box!.y + box!.height).toBeCloseTo(844, 0)
  await nav.getByRole('link', { name: '看板' }).click()
  await expect(page.getByRole('heading', { level: 1, name: '看板' })).toBeVisible()
  await expect(nav.getByRole('link', { name: '看板' })).toHaveAttribute('aria-current', 'page')
})
