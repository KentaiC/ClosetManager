import { useEffect, useState, type FormEvent, type ReactNode } from 'react'
import { api } from '../../api/client'
import type { ApiItem, ItemUpdate } from '../../api/types'
import { useCapabilities } from '../../app/capabilities'
import { useMeta } from '../../app/meta'
import { seasonsForScore, warmthLevelFor } from '../../app/warmth'
import { ChipMulti } from '../../components/Chips'
import { FilePicker, IMAGE_ACCEPT } from '../../components/FilePicker'
import { useImageIngest, type IngestResult } from '../items/useImageIngest'

type Color = ItemUpdate['dominantColor']

/** 把 #RRGGBB 转为 0 到 1 的 sRGB 分量。 */
export function hexToColor(hex: string): ItemUpdate['dominantColor'] {
  const value = Number.parseInt(hex.replace('#', ''), 16)
  return { red: ((value >> 16) & 0xff) / 255, green: ((value >> 8) & 0xff) / 255, blue: (value & 0xff) / 255, alpha: 1 }
}

/** 编辑表单的初始值，规则与 App 的 ItemDraftModel(editing:) 相同。 */
export function draftFromItem(item: ApiItem): ItemDraft {
  return {
    name: item.name,
    category: item.category,
    subtype: item.subtype,
    scenarios: item.scenarios,
    warmthScore: item.warmthScore,
    seasons: item.seasons,
    seasonsManuallyEdited: item.seasons.length > 0,
    status: item.status,
    isWaterproof: item.isWaterproof,
    brand: item.brand ?? '',
    notes: item.notes ?? '',
    colorHex: item.dominantColor.hex,
    colorChanged: false,
    baseColor: { red: item.dominantColor.red, green: item.dominantColor.green, blue: item.dominantColor.blue, alpha: item.dominantColor.alpha },
    images: undefined,
    hasImage: item.images.display !== undefined,
  }
}

/** 新增单品的初始值，与 App 的 ItemDraftModel() 相同：上装、保暖度 50、中性灰、季节为空。 */
export function newDraft(): ItemDraft {
  return {
    name: '',
    category: 'top',
    subtype: null,
    scenarios: [],
    warmthScore: 50,
    seasons: [],
    seasonsManuallyEdited: false,
    status: 'inWardrobe',
    isWaterproof: false,
    brand: '',
    notes: '',
    colorHex: '#808080',
    colorChanged: false,
    baseColor: { red: 0.5, green: 0.5, blue: 0.5, alpha: 1 },
    images: undefined,
    hasImage: false,
  }
}

export interface ItemDraft {
  name: string
  category: string
  subtype: string | null
  scenarios: string[]
  warmthScore: number
  seasons: string[]
  seasonsManuallyEdited: boolean
  status: string
  isWaterproof: boolean
  brand: string
  notes: string
  colorHex: string
  colorChanged: boolean
  /** 未手动改色时提交的颜色分量：单品原有的颜色或取色结果，避免十六进制取整改变数据。 */
  baseColor: Color
  /** 新上传的图片；未更换图片时为 undefined。 */
  images: ItemUpdate['images']
  hasImage: boolean
}

/** 把一次抠图取色的结果应用到草稿，与 App 处理新图片后更新图片与主辅色相同。不支持取色时保留原来的主色。 */
export function applyIngest(draft: ItemDraft, result: IngestResult): ItemDraft {
  const color = result.dominantColor
  return {
    ...draft,
    hasImage: true,
    images: {
      original: result.original.sha256,
      ...(result.processed ? { processed: result.processed.sha256 } : {}),
      ...(result.secondaryColor
        ? { secondaryColor: { red: result.secondaryColor.red, green: result.secondaryColor.green, blue: result.secondaryColor.blue, alpha: result.secondaryColor.alpha } }
        : {}),
    },
    ...(color
      ? { colorHex: color.hex, colorChanged: false, baseColor: { red: color.red, green: color.green, blue: color.blue, alpha: color.alpha } }
      : {}),
  }
}

/** 草稿转为提交内容。 */
export function updateFromDraft(draft: ItemDraft): ItemUpdate {
  return {
    name: draft.name,
    category: draft.category,
    subtype: draft.subtype,
    scenarios: draft.scenarios,
    warmthScore: draft.warmthScore,
    seasons: draft.seasons,
    status: draft.status,
    isWaterproof: draft.isWaterproof,
    brand: draft.brand,
    notes: draft.notes,
    dominantColor: draft.colorChanged ? hexToColor(draft.colorHex) : draft.baseColor,
    ...(draft.images ? { images: draft.images } : {}),
  }
}

/**
 * 单品录入与编辑表单，字段与 App 的 ItemFormSections 对应。
 * 名称留空时保存为「颜色 + 子类」默认名称；与 App 相同，没有图片或图片处理中时不能保存。
 */
export function ItemEditor({
  item,
  initialFile,
  allowsImagePicker = true,
  onSubmit,
  onSaved,
  onCancel,
  renderActions,
}: {
  /** 编辑的单品；不传时为新增。 */
  item?: ApiItem
  /** 批量录入时预置的图片，挂载后立即处理。 */
  initialFile?: File
  allowsImagePicker?: boolean
  onSubmit: (update: ItemUpdate) => Promise<ApiItem>
  onSaved: (item: ApiItem) => void
  onCancel?: () => void
  /** 自定义底部按钮，批量录入用它显示「跳过这张」「保存并下一件」。 */
  renderActions?: (actions: { canSave: boolean; saving: boolean; save: () => void }) => ReactNode
}) {
  const meta = useMeta()
  const [draft, setDraft] = useState<ItemDraft>(() => (item ? draftFromItem(item) : newDraft()))
  const [defaultName, setDefaultName] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const { state: ingestState, ingest } = useImageIngest()
  const category = meta.meta.categories.find((entry) => entry.value === draft.category)
  const busy = ingestState.phase === 'uploading' || ingestState.phase === 'processing'
  const canSave = draft.hasImage && !busy && !saving

  async function handleFile(file: File) {
    const result = await ingest(file)
    if (result) setDraft((current) => applyIngest(current, result))
  }

  useEffect(() => {
    if (initialFile) void handleFile(initialFile)
    // 只在挂载时处理预置图片。
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // 默认名称由服务端按共享核心规则计算。
  useEffect(() => {
    let current = true
    const timer = setTimeout(() => {
      api.defaultName(draft.category, draft.subtype, draft.colorHex).then(
        (name) => current && setDefaultName(name),
        () => current && setDefaultName(''),
      )
    }, 150)
    return () => {
      current = false
      clearTimeout(timer)
    }
  }, [draft.category, draft.subtype, draft.colorHex])

  function update(patch: Partial<ItemDraft>) {
    setDraft((current) => ({ ...current, ...patch }))
  }

  function changeCategory(value: string) {
    const subtypes = meta.meta.categories.find((entry) => entry.value === value)?.subtypes ?? []
    // 切换分类后清理不匹配的子类（ItemDraftModel.reconcileSubtype）。
    update({ category: value, subtype: subtypes.some((s) => s.value === draft.subtype) ? draft.subtype : null })
  }

  function changeWarmth(score: number) {
    // 季节未手动调整时随保暖度自动推导（ItemDraftModel.deriveSeasonsIfNeeded）。
    update({ warmthScore: score, ...(draft.seasonsManuallyEdited ? {} : { seasons: seasonsForScore(meta.meta, score) }) })
  }

  const conflicting = meta.meta.scenarios.some(
    (scenario) => draft.scenarios.includes(scenario.value) && scenario.conflictsWith.some((other) => draft.scenarios.includes(other)),
  )

  async function save() {
    if (!canSave) return
    setSaving(true)
    setError(null)
    try {
      onSaved(await onSubmit(updateFromDraft(draft)))
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setSaving(false)
    }
  }

  function submit(event: FormEvent) {
    event.preventDefault()
    void save()
  }

  const level = warmthLevelFor(meta.meta, draft.warmthScore)

  return (
    <form className="form" onSubmit={submit} aria-label={item ? '编辑单品' : '新增单品'}>
      <ImageSection item={item} ingestState={ingestState} allowsPicker={allowsImagePicker} busy={busy}
        hasImage={draft.hasImage} onFile={(file) => void handleFile(file)} />

      <fieldset>
        <legend>基本信息</legend>
        <label className="form-row">
          <span>名称</span>
          <input value={draft.name} placeholder={defaultName} onChange={(event) => update({ name: event.target.value })} />
        </label>
        {draft.name === '' && <p className="hint">名称已按「颜色 + 子类」自动生成，可直接修改。</p>}
        <label className="form-row">
          <span>分类</span>
          <select value={draft.category} onChange={(event) => changeCategory(event.target.value)}>
            {meta.meta.categories.map((option) => (
              <option key={option.value} value={option.value}>
                {option.displayName}
              </option>
            ))}
          </select>
        </label>
        <label className="form-row">
          <span>子类</span>
          <select value={draft.subtype ?? ''} onChange={(event) => update({ subtype: event.target.value || null })}>
            <option value="">未指定</option>
            {category?.subtypes.map((option) => (
              <option key={option.value} value={option.value}>
                {option.displayName}
              </option>
            ))}
          </select>
        </label>
      </fieldset>

      <fieldset>
        <legend>颜色</legend>
        <label className="form-row">
          <span>主色</span>
          <input type="color" value={draft.colorHex} onChange={(event) => update({ colorHex: event.target.value.toUpperCase(), colorChanged: true })} />
        </label>
        <p className="hint">自动提取主辅色；可在此手动调整主色。</p>
      </fieldset>

      <fieldset>
        <legend>适用场景</legend>
        <ChipMulti options={meta.meta.scenarios} values={draft.scenarios} onChange={(scenarios) => update({ scenarios })} />
        {conflicting && <p className="hint warning">「正式」与「运动」相互冲突，建议不要同时选择。</p>}
      </fieldset>

      <fieldset>
        <legend>保暖度</legend>
        <label className="form-row">
          <span>
            保暖度 {draft.warmthScore}（{meta.name('warmthLevel', level)}）
          </span>
          <input
            type="range"
            min={1}
            max={100}
            step={1}
            value={draft.warmthScore}
            onChange={(event) => changeWarmth(Number(event.target.value))}
          />
        </label>
        <p className="hint">1 最薄（短袖）到 100 最厚（羽绒）。叠穿算法据此做「保暖度求和匹配气温」。</p>
      </fieldset>

      <fieldset>
        <legend>适用季节</legend>
        <ChipMulti
          options={meta.meta.seasons}
          values={draft.seasons}
          onChange={(seasons) => update({ seasons, seasonsManuallyEdited: true })}
        />
        {draft.seasonsManuallyEdited ? (
          <button
            type="button"
            className="link-button"
            onClick={() => update({ seasonsManuallyEdited: false, seasons: seasonsForScore(meta.meta, draft.warmthScore) })}
          >
            恢复为按保暖程度自动匹配
          </button>
        ) : (
          <p className="hint">默认由保暖程度自动推导，可手动调整。</p>
        )}
      </fieldset>

      <fieldset>
        <legend>状态</legend>
        <div className="segmented" role="radiogroup" aria-label="当前状态">
          {meta.meta.statuses.map((option) => (
            <button
              key={option.value}
              type="button"
              role="radio"
              aria-checked={draft.status === option.value}
              className={draft.status === option.value ? 'selected' : ''}
              onClick={() => update({ status: option.value })}
            >
              {option.displayName}
            </button>
          ))}
        </div>
        <label className="toggle">
          <input type="checkbox" checked={draft.isWaterproof} onChange={(event) => update({ isWaterproof: event.target.checked })} />
          防水 / 防泼水
        </label>
        <p className="hint">一般通过「脱下穿搭」自动流转；防水属性供雨雪天气穿搭强关联使用。</p>
      </fieldset>

      <fieldset>
        <legend>其它（可选）</legend>
        <label className="form-row">
          <span>品牌</span>
          <input value={draft.brand} onChange={(event) => update({ brand: event.target.value })} />
        </label>
        <label className="form-row">
          <span>备注</span>
          <textarea rows={3} value={draft.notes} onChange={(event) => update({ notes: event.target.value })} />
        </label>
      </fieldset>

      {error && <p className="form-error" role="alert">{error}</p>}
      {!draft.hasImage && !busy && <p className="hint">请先添加图片。</p>}
      {renderActions ? (
        renderActions({ canSave, saving, save: () => void save() })
      ) : (
        <div className="form-actions">
          <button type="button" className="button" onClick={onCancel}>
            取消
          </button>
          <button type="submit" className="button button-primary" disabled={!canSave}>
            保存
          </button>
        </div>
      )}
    </form>
  )
}

/** 图片区，对应 App ItemFormSections 的 imageSection：预览、选图按钮与处理状态。 */
function ImageSection({
  item,
  ingestState,
  allowsPicker,
  busy,
  hasImage,
  onFile,
}: {
  item?: ApiItem
  ingestState: ReturnType<typeof useImageIngest>['state']
  allowsPicker: boolean
  busy: boolean
  hasImage: boolean
  onFile: (file: File) => void
}) {
  const capabilities = useCapabilities()
  const preview = ingestState.phase === 'done' ? (ingestState.processed ?? ingestState.original) : undefined
  let body: ReactNode
  if (ingestState.phase === 'uploading') {
    body = <span className="muted">正在上传…</span>
  } else if (ingestState.phase === 'processing') {
    body = <span className="muted">{capabilities.backgroundRemoval ? '正在本地抠图…' : '正在处理…'}</span>
  } else if (preview) {
    body = preview.displayable ? <img src={preview.url} alt="图片预览" /> : <span className="muted">浏览器无法显示这种格式的预览，保存后仍会保留原图。</span>
  } else if (item?.images.display) {
    body = item.images.display.displayable ? <img src={item.images.display.url} alt={item.title} /> : <span className="muted">HEIC</span>
  } else {
    body = <span className="muted">尚未选择图片</span>
  }

  const notes: ReactNode[] = []
  if (ingestState.phase === 'error') {
    notes.push(<p key="error" className="form-error" role="alert">{ingestState.message}</p>)
  } else if (ingestState.phase === 'done') {
    if (ingestState.failure) notes.push(<p key="failure" className="hint warning">{ingestState.failure}</p>)
    else if (!ingestState.processed)
      notes.push(
        <p key="original" className="hint">
          {capabilities.backgroundRemoval ? '已使用原图（未识别到主体或尚未完成去背）。' : '当前服务不支持本地抠图，已使用原图。'}
        </p>,
      )
    if (!ingestState.dominantColor) notes.push(<p key="color" className="hint">当前服务不支持自动取色，请在下方手动选择主色。</p>)
  }

  return (
    <fieldset>
      <legend>图片</legend>
      <div className="image-preview" data-testid="image-preview">{body}</div>
      {allowsPicker && (
        <FilePicker label={hasImage ? '更换图片' : '添加图片'} accept={IMAGE_ACCEPT} disabled={busy} onFiles={(files) => files[0] && onFile(files[0])} />
      )}
      {notes}
    </fieldset>
  )
}
