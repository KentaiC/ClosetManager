import { expect, test, type Page } from '@playwright/test'
import { BOOTS_ID, BOTTOM_ID, trackPageErrors } from './support'

// 这些流程按顺序修改同一份样例数据，模拟一次完整使用：
// 脱下当前穿搭并洗净，结束差旅，补全单品信息，生成并穿着穿搭，查看看板，最后删除。
test.describe.configure({ mode: 'serial' })

async function nav(page: Page, name: string) {
  await page.getByRole('navigation', { name: '主导航' }).getByRole('link', { name }).click()
  await expect(page.getByRole('heading', { level: 1, name })).toBeVisible()
}

test('take off the current outfit, then wash everything in the laundry', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/')
  await page.getByRole('button', { name: '脱下并扔进洗衣袋' }).click()
  const dialog = page.getByRole('dialog', { name: '脱下穿搭' })
  await expect(dialog.getByRole('checkbox')).toHaveCount(1)
  await expect(dialog.getByRole('checkbox')).toBeChecked()
  await dialog.getByRole('button', { name: '按勾选脱下' }).click()
  await expect(page.getByTestId('active-outfit-empty')).toHaveText('今天尚未选择穿搭')

  await nav(page, '洗衣房')
  const grid = page.getByTestId('laundry-grid')
  await expect(grid.getByRole('button')).toHaveCount(2)
  await expect(grid.getByRole('button', { name: '下装' })).toContainText('久置·快洗')
  await expect(grid.getByRole('button', { name: '白色T恤' })).not.toContainText('久置·快洗')
  await page.getByRole('button', { name: '全选' }).click()
  await page.getByRole('button', { name: '洗净放回（2）' }).click()
  await expect(page.getByText('洗衣袋是空的')).toBeVisible()
  assertNoErrors()
})

test('end the trip from the travel packer', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/settings')
  await page.getByRole('link', { name: '差旅打包' }).click()
  await expect(page.getByRole('heading', { name: '差旅打包' })).toBeVisible()
  await expect(page.getByTestId('essentials')).toContainText('内裤 / 打底：4 条')
  const luggage = page.getByTestId('luggage')
  await expect(luggage).toContainText('行李箱（1 件）')
  await luggage.getByRole('button', { name: '结束差旅，全部取出' }).click()
  await expect(page.getByText('已结束差旅，全部取出')).toBeVisible()
  await expect(luggage).toHaveCount(0)
  assertNoErrors()
})

test('give the unnamed bottom a scenario so it can be used in outfits', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto(`/items/${BOTTOM_ID}`)
  await expect(page.getByRole('heading', { level: 1, name: '下装' })).toBeVisible()
  await page.getByRole('button', { name: '编辑' }).click()
  const form = page.getByRole('form', { name: '编辑单品' })
  const name = form.getByLabel('名称')
  await expect(name).toHaveValue('')
  await expect(name).not.toHaveAttribute('placeholder', '')
  const defaultName = await name.getAttribute('placeholder')
  await form.getByRole('group', { name: '适用场景' }).getByRole('button', { name: '休闲' }).click()
  await form.getByRole('button', { name: '保存' }).click()
  await expect(page.getByText('已保存')).toBeVisible()
  // 名称留空时服务端按 App 规则保存为默认名称。
  await expect(page.getByRole('heading', { level: 1, name: defaultName! })).toBeVisible()
  await expect(page.getByText('休闲', { exact: true })).toBeVisible()
  assertNoErrors()
})

test('generate an outfit, save it and wear it today', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/outfits')
  await page.getByRole('button', { name: '生成穿搭' }).click()
  const card = page.getByTestId('outfit-draft').first()
  await expect(card).toBeVisible()
  await expect(card.locator('.draft-label')).toHaveText(['上装', '下装', '鞋子'])
  await card.getByRole('button', { name: '加入收藏' }).click()
  await expect(page.getByText('已加入收藏')).toBeVisible()
  await card.getByRole('button', { name: '今天穿这套' }).click()
  await expect(page.getByText('已设为今天穿这套')).toBeVisible()

  await page.getByRole('tab', { name: '收藏夹' }).click()
  await expect(page.getByTestId('favorite-outfit')).toHaveCount(2)

  await nav(page, '衣橱')
  await expect(page.getByTestId('active-outfit').locator('.thumb-wrap')).toHaveCount(3)
  assertNoErrors()
})

test('build an outfit by hand', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/outfits')
  await page.getByRole('tab', { name: '自由拼搭' }).click()
  const save = page.getByRole('button', { name: '加入收藏' })
  await expect(save).toBeDisabled()
  // 正在穿的单品仍在衣橱中，可以选择。
  await page.getByRole('region', { name: '上装' }).getByRole('button').first().click()
  await page.getByRole('region', { name: '下装' }).getByRole('button').first().click()
  await page.getByRole('region', { name: '鞋子' }).getByRole('button', { name: '防水靴' }).click()
  await expect(save).toBeEnabled()
  await save.click()
  await expect(page.getByText('已加入收藏')).toBeVisible()
  await page.getByRole('tab', { name: '收藏夹' }).click()
  await expect(page.getByTestId('favorite-outfit')).toHaveCount(3)
  assertNoErrors()
})

test('the dashboard and calendar reflect today', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/analytics')
  const today = await page.evaluate(() => {
    const now = new Date()
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`
  })
  const heatmap = page.getByRole('list', { name: '最近 16 周的穿着次数' })
  await expect(heatmap.locator(`[data-date="${today}"]`)).toHaveClass(/heat-1/)
  await expect(page.getByRole('list', { name: '衣橱颜色占比' }).getByRole('listitem')).toHaveCount(3)

  await nav(page, '日历')
  const records = page.getByTestId('wear-record')
  await expect(records).toHaveCount(3)
  await expect(records.first()).toContainText('正在穿')
  assertNoErrors()
})

test('search combines filters', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/')
  await page.getByRole('link', { name: '高级筛选' }).click()
  await expect(page.getByTestId('result-count')).toHaveText('共 3 件')
  await page.getByLabel('场景').selectOption('casual')
  await expect(page.getByTestId('result-count')).toHaveText('共 3 件')
  await page.getByLabel('仅防水单品').check()
  await expect(page.getByTestId('result-count')).toHaveText('共 1 件')
  await expect(page.getByRole('link', { name: '防水靴' })).toBeVisible()
  assertNoErrors()
})

test('profile is stored by the server and appearance by the browser', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/settings')
  const profile = page.getByRole('form', { name: '个人资料' })
  await profile.getByLabel('身高（cm）').fill('172.5')
  await profile.getByLabel('性别').selectOption('female')
  await profile.getByRole('button', { name: '保存' }).click()
  await expect(page.getByText('已保存')).toBeVisible()
  await page.getByLabel('外观模式').selectOption('dark')
  await page.getByRole('radio', { name: '蓝色' }).click()

  await page.reload()
  await expect(profile.getByLabel('身高（cm）')).toHaveValue('172.5')
  await expect(profile.getByLabel('性别')).toHaveValue('female')
  await expect(page.locator('html')).toHaveAttribute('data-theme', 'dark')
  await expect.poll(() => page.evaluate(() => getComputedStyle(document.documentElement).getPropertyValue('--accent').trim())).toBe('#007AFF')
  assertNoErrors()
})

test('delete a favourite, a wear record and an item', async ({ page }) => {
  const assertNoErrors = trackPageErrors(page)
  await page.goto('/outfits')
  await page.getByRole('tab', { name: '收藏夹' }).click()
  await page.getByTestId('favorite-outfit').first().getByRole('button', { name: '删除' }).click()
  await page.getByRole('dialog').getByRole('button', { name: '删除' }).click()
  await expect(page.getByTestId('favorite-outfit')).toHaveCount(2)

  await nav(page, '日历')
  await page.getByTestId('wear-record').last().getByRole('button', { name: '删除' }).click()
  await page.getByRole('dialog').getByRole('button', { name: '删除' }).click()
  await expect(page.getByTestId('wear-record')).toHaveCount(2)

  await page.goto(`/items/${BOOTS_ID}`)
  await page.getByRole('button', { name: '删除' }).click()
  await page.getByRole('dialog', { name: '删除「防水靴」？' }).getByRole('button', { name: '删除' }).click()
  await expect(page.getByRole('heading', { name: '我的衣橱' })).toBeVisible()
  await expect(page.getByTestId('gallery').getByRole('link', { name: '防水靴' })).toHaveCount(0)
  assertNoErrors()

  // 浏览器会把 404 响应记为控制台错误，所以在错误检查之后再访问已删除的单品。
  await page.goto(`/items/${BOOTS_ID}`)
  await expect(page.getByText('未找到该单品')).toBeVisible()
})
