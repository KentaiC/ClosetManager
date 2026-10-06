import { expect, test } from '@playwright/test'
import { TEE_ID, trackPageErrors } from './support'

test('gallery follows the app visibility rules', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  const response = await page.goto('/')
  expect(response?.headers()['content-security-policy']).toContain("default-src 'self'")

  await expect(page.getByRole('heading', { name: '我的衣橱' })).toBeVisible()
  const gallery = page.getByTestId('gallery')
  await expect(gallery.getByRole('link')).toHaveCount(1)
  await expect(gallery.getByRole('link', { name: '白色T恤' })).toBeVisible()

  await page.getByLabel('显示洗衣袋内衣物').check()
  await expect(gallery.getByRole('link')).toHaveCount(2)
  await expect(gallery.getByRole('link', { name: '下装' })).toBeVisible()
  await expect(gallery.getByRole('link', { name: '防水靴' })).toHaveCount(0)

  await page.getByRole('button', { name: '鞋子' }).click()
  await expect(page.getByText('该分类下没有可显示的单品')).toBeVisible()
  await page.getByRole('button', { name: '全部' }).click()

  await expect(page.getByTestId('active-outfit')).toContainText('目前正在穿')
  assertNoErrors()
})

test('images load from the content-addressed store', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/')
  const image = page.getByTestId('gallery').getByRole('img', { name: '白色T恤' })
  await expect(image).toBeVisible()
  await expect.poll(() => image.evaluate((element: HTMLImageElement) => element.complete && element.naturalWidth)).toBe(1)
  assertNoErrors()
})

test('size preference survives a reload', async ({ page }) => {
  await page.goto('/')
  await page.getByRole('button', { name: '小' }).click()
  await expect(page.getByTestId('gallery')).toHaveClass(/gallery-small/)
  await page.reload()
  await expect(page.getByTestId('gallery')).toHaveClass(/gallery-small/)
})

test('detail page opens from a card and from a deep link', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/')
  await page.getByRole('link', { name: '白色T恤' }).click()
  await expect(page).toHaveURL(new RegExp(`/items/${TEE_ID}$`))
  await expect(page.getByRole('heading', { name: '白色T恤' })).toBeVisible()
  await expect(page.getByText('上装 · T恤')).toBeVisible()
  await expect(page.getByText('通勤、休闲')).toBeVisible()

  await page.goto(`/items/${TEE_ID}`)
  await expect(page.getByRole('heading', { name: '白色T恤' })).toBeVisible()
  await page.getByRole('link', { name: '返回衣橱' }).click()
  await expect(page.getByRole('heading', { name: '我的衣橱' })).toBeVisible()
  assertNoErrors()
})

test('navigation reaches every tab and browser history works', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/')
  for (const name of ['洗衣房', '穿搭', '日历', '看板']) {
    await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name }).click()
    await expect(page.getByRole('heading', { name })).toBeVisible()
  }
  await page.goBack()
  await expect(page.getByRole('heading', { name: '日历' })).toBeVisible()
  assertNoErrors()
})

test('the server rejects cross-site writes and foreign hosts', async ({ request }) => {
  const write = await request.post('/api/v1/items', { data: {} })
  expect(write.status()).toBe(403)
  expect((await write.json()).error.code).toBe('request_rejected')
  const foreign = await request.get('/api/v1/health', { headers: { Host: 'evil.example' } })
  expect(foreign.status()).toBe(403)
})
