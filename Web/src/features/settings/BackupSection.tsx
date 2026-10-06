import { useState } from 'react'
import { api } from '../../api/client'
import type { ApiImportReport } from '../../api/types'
import { Dialog } from '../../app/Dialog'
import { useDataVersion } from '../../app/dataVersion'
import { useToast } from '../../app/toast'
import { FilePicker } from '../../components/FilePicker'

type Mode = 'merge' | 'overwrite'

/** 报告摘要，与 closet-server import 的输出相同。 */
export function reportLines(report: ApiImportReport): string[] {
  return [
    `单品：备份 ${report.items.inBackup}，导入 ${report.items.toImport}，跳过 ${report.items.skippedExisting}`,
    `穿搭：备份 ${report.outfits.inBackup}，导入 ${report.outfits.toImport}，跳过 ${report.outfits.skippedExisting}`,
    `穿着记录：备份 ${report.wearRecords.inBackup}，导入 ${report.wearRecords.toImport}，跳过 ${report.wearRecords.skippedExisting}`,
    `图片：${report.imageCount} 张`,
  ]
}

/** 让浏览器保存一个文件。 */
function saveFile(blob: Blob, fileName: string) {
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  document.body.append(link)
  link.click()
  link.remove()
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

/**
 * 数据冷备份，对应 App 设置页的备份区：导出 .wardrobe 文件，导入时选择覆盖或合并。
 * 导入先预检并显示报告，确认后才写入；写入前服务端会自动保存一份当前数据。
 */
export function BackupSection() {
  const toast = useToast()
  const { invalidate } = useDataVersion()
  const [exporting, setExporting] = useState(false)
  const [file, setFile] = useState<File | null>(null)
  const [mode, setMode] = useState<Mode | null>(null)
  const [report, setReport] = useState<ApiImportReport | null>(null)
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState<string | null>(null)

  async function exportBackup() {
    setExporting(true)
    try {
      const { blob, fileName } = await api.exportBackup()
      saveFile(blob, fileName)
      toast('已生成备份文件')
    } catch (e) {
      toast(`生成备份失败：${e instanceof Error ? e.message : String(e)}`)
    } finally {
      setExporting(false)
    }
  }

  function close() {
    setFile(null)
    setMode(null)
    setReport(null)
    setError(null)
  }

  async function run(chosen: Mode, apply: boolean) {
    if (!file) return
    setMode(chosen)
    setBusy(true)
    setError(null)
    try {
      const result = await api.importBackup(file, chosen, apply)
      setReport(result)
      if (result.applied) invalidate()
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
    } finally {
      setBusy(false)
    }
  }

  const done = report?.applied === true
  return (
    <fieldset className="form">
      <legend>数据冷备份</legend>
      <div className="row-actions">
        <button type="button" className="button" onClick={exportBackup} disabled={exporting}>
          生成并下载备份文件
        </button>
        <FilePicker label="导入备份" accept=".wardrobe,application/json,application/octet-stream" onFiles={(files) => setFile(files[0] ?? null)} />
      </div>
      <p className="hint">备份为单个 .wardrobe 文件（含图片），与 App 的备份文件通用。导入前会自动保存一份当前数据。</p>

      {file && (
        <Dialog
          title="导入方式"
          onClose={close}
          footer={
            done ? (
              <button type="button" className="button button-primary" onClick={close}>
                完成
              </button>
            ) : report && mode ? (
              <>
                <button type="button" className="button" onClick={close}>
                  取消
                </button>
                <button
                  type="button"
                  className={`button ${mode === 'overwrite' ? 'button-danger' : 'button-primary'}`}
                  onClick={() => run(mode, true)}
                  disabled={busy || report.errors.length > 0}
                >
                  确认导入
                </button>
              </>
            ) : (
              <>
                <button type="button" className="button" onClick={close}>
                  取消
                </button>
                <button type="button" className="button" onClick={() => run('merge', false)} disabled={busy}>
                  与现有数据合并
                </button>
                <button type="button" className="button button-danger" onClick={() => run('overwrite', false)} disabled={busy}>
                  覆盖现有数据
                </button>
              </>
            )
          }
        >
          <p className="muted">文件：{file.name}</p>
          {busy && <p className="muted">{report ? '正在导入…' : '正在检查备份文件…'}</p>}
          {error && <p className="form-error" role="alert">{error}</p>}
          {report && (
            <div data-testid="import-report">
              <p>
                <strong>
                  {done ? '导入完成。' : report.errors.length > 0 ? '预检发现错误，未写入数据。' : mode === 'overwrite' ? '预检通过。覆盖会先清空现有的单品、穿搭与穿着记录。' : '预检通过。合并会跳过已存在的记录。'}
                </strong>
              </p>
              <ul className="report-lines">
                {reportLines(report).map((line) => <li key={line}>{line}</li>)}
              </ul>
              {report.errors.map((issue, index) => (
                <p key={`e${index}`} className="form-error">错误：{issue.message}</p>
              ))}
              {report.warnings.map((issue, index) => (
                <p key={`w${index}`} className="hint warning">警告：{issue.message}</p>
              ))}
              {done && report.preImportBackup && <p className="hint">导入前的数据已备份为 backups/before-import/{report.preImportBackup}</p>}
            </div>
          )}
        </Dialog>
      )}
    </fieldset>
  )
}
