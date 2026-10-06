import { render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { App } from '../../App'
import type { ApiImportReport } from '../../api/types'
import { byMethod, json, mockFetch, profileFixture, standardRoutes } from '../../test/fixtures'
import { reportLines } from './BackupSection'

const preview: ApiImportReport = {
  mode: 'merge',
  dryRun: true,
  backupVersion: 1,
  items: { inBackup: 3, toImport: 1, skippedExisting: 2 },
  outfits: { inBackup: 1, toImport: 0, skippedExisting: 1 },
  wearRecords: { inBackup: 2, toImport: 0, skippedExisting: 2 },
  imageCount: 2,
  imageBytes: 92,
  warnings: [{ code: 'missing_reference', message: '穿搭引用了不存在的单品，已跳过该成员。' }],
  errors: [],
  applied: false,
}

const backupFile = () => new File(['{"version":1}'], 'ClosetBackup.wardrobe', { type: '' })

function openSettings(importHandler: (url: URL, init: RequestInit | undefined) => Response) {
  const calls = mockFetch({
    ...standardRoutes,
    '/api/v1/settings/profile': () => json(profileFixture),
    '/api/v1/backup/import': byMethod({ POST: importHandler }),
    '/api/v1/backup/export': byMethod({
      POST: () =>
        new Response('{"version":1}', {
          headers: { 'Content-Type': 'application/octet-stream', 'Content-Disposition': 'attachment; filename="ClosetBackup-2026-10-07T00-00-00Z.wardrobe"' },
        }),
    }),
  })
  window.history.replaceState(null, '', '/settings')
  render(<App />)
  return calls
}

describe('BackupSection', () => {
  const created: string[] = []
  beforeEach(() => {
    URL.createObjectURL = vi.fn(() => 'blob:backup')
    URL.revokeObjectURL = vi.fn()
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      created.push(this.download)
    })
  })
  afterEach(() => {
    vi.restoreAllMocks()
    created.length = 0
  })

  it('downloads the backup under the server file name', async () => {
    const calls = openSettings(() => json(preview))
    await userEvent.click(await screen.findByRole('button', { name: '生成并下载备份文件' }))
    expect(await screen.findByText('已生成备份文件')).toBeInTheDocument()
    expect(created).toEqual(['ClosetBackup-2026-10-07T00-00-00Z.wardrobe'])
    const exportCall = calls.find((call) => call.url.pathname === '/api/v1/backup/export')!
    expect((exportCall.init?.headers as Record<string, string>)['X-Closet-Client']).toBe('web')
  })

  it('previews, then imports after confirmation', async () => {
    const calls = openSettings((url) =>
      url.searchParams.get('apply') === 'true'
        ? json({ ...preview, dryRun: false, applied: true, preImportBackup: 'ClosetBackup-2026-10-06T22-00-00Z.wardrobe' })
        : json(preview),
    )
    await userEvent.upload(await screen.findByLabelText('导入备份'), backupFile())
    const dialog = screen.getByRole('dialog', { name: '导入方式' })
    expect(within(dialog).getByText('文件：ClosetBackup.wardrobe')).toBeInTheDocument()

    await userEvent.click(within(dialog).getByRole('button', { name: '与现有数据合并' }))
    expect(await within(dialog).findByText('预检通过。合并会跳过已存在的记录。')).toBeInTheDocument()
    expect(within(dialog).getByText('单品：备份 3，导入 1，跳过 2')).toBeInTheDocument()
    expect(within(dialog).getByText('警告：穿搭引用了不存在的单品，已跳过该成员。')).toBeInTheDocument()

    await userEvent.click(within(dialog).getByRole('button', { name: '确认导入' }))
    expect(await within(dialog).findByText('导入完成。')).toBeInTheDocument()
    expect(within(dialog).getByText('导入前的数据已备份为 backups/before-import/ClosetBackup-2026-10-06T22-00-00Z.wardrobe')).toBeInTheDocument()
    const requests = calls.filter((call) => call.url.pathname === '/api/v1/backup/import')
    expect(requests.map((call) => Object.fromEntries(call.url.searchParams))).toEqual([
      { mode: 'merge', apply: 'false' },
      { mode: 'merge', apply: 'true' },
    ])
    expect(requests[0]!.init?.body).toBeInstanceOf(Blob)
    await userEvent.click(within(dialog).getByRole('button', { name: '完成' }))
    expect(screen.queryByRole('dialog')).not.toBeInTheDocument()
  })

  it('blocks importing a file with errors and explains overwrite', async () => {
    openSettings(() => json({ ...preview, mode: 'overwrite', errors: [{ code: 'invalid_value', message: '单品的分类「hats」无效。' }] }))
    await userEvent.upload(await screen.findByLabelText('导入备份'), backupFile())
    const dialog = screen.getByRole('dialog', { name: '导入方式' })
    await userEvent.click(within(dialog).getByRole('button', { name: '覆盖现有数据' }))
    expect(await within(dialog).findByText('预检发现错误，未写入数据。')).toBeInTheDocument()
    expect(within(dialog).getByText('错误：单品的分类「hats」无效。')).toBeInTheDocument()
    expect(within(dialog).getByRole('button', { name: '确认导入' })).toBeDisabled()
  })

  it('shows why an unreadable file was rejected', async () => {
    openSettings(() => json({ error: { code: 'invalid_backup', message: '无法读取备份文件，请确认它是 App 导出的 .wardrobe 文件。' } }, 400))
    await userEvent.upload(await screen.findByLabelText('导入备份'), backupFile())
    await userEvent.click(within(screen.getByRole('dialog')).getByRole('button', { name: '与现有数据合并' }))
    expect(await screen.findByRole('alert')).toHaveTextContent('无法读取备份文件')
  })

  it('summarises a report like the command line', () => {
    expect(reportLines(preview)).toEqual([
      '单品：备份 3，导入 1，跳过 2',
      '穿搭：备份 1，导入 0，跳过 1',
      '穿着记录：备份 2，导入 0，跳过 2',
      '图片：2 张',
    ])
  })
})
