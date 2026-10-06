import { useEffect, useState, type FormEvent } from 'react'
import { api } from '../../api/client'
import type { ApiItem, ItemUpdate } from '../../api/types'
import { useMeta } from '../../app/meta'
import { seasonsForScore, warmthLevelFor } from '../../app/warmth'
import { ChipMulti } from '../../components/Chips'

/** 把 #RRGGBB 转为 0 到 1 的 sRGB 分量。 */
export function hexToColor(hex: string): ItemUpdate['dominantColor'] {
  const value = Number.parseInt(hex.replace('#', ''), 16)
  return { red: ((value >> 16) & 0xff) / 255, green: ((value >> 8) & 0xff) / 255, blue: (value & 0xff) / 255, alpha: 1 }
}

/** 编辑表单的初始值，规则与 App 的 ItemDraftModel(editing:) 相同。 */
export function draftFromItem(item: ApiItem) {
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
  }
}

export type ItemDraft = ReturnType<typeof draftFromItem>

/**
 * 单品编辑表单，字段与 App 的 ItemFormSections 对应（图片区在后续阶段接入）。
 * 名称留空时保存为「颜色 + 子类」默认名称，与 App 相同。
 */
export function ItemEditor({ item, onSaved, onCancel }: { item: ApiItem; onSaved: (item: ApiItem) => void; onCancel: () => void }) {
  const meta = useMeta()
  const [draft, setDraft] = useState<ItemDraft>(() => draftFromItem(item))
  const [defaultName, setDefaultName] = useState('')
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState<string | null>(null)
  const category = meta.meta.categories.find((entry) => entry.value === draft.category)

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

  async function submit(event: FormEvent) {
    event.preventDefault()
    setSaving(true)
    setError(null)
    try {
      const saved = await api.updateItem(item.id, {
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
        // 未修改颜色时原样提交存储值，避免十六进制取整改变数据。
        dominantColor: draft.colorChanged ? hexToColor(draft.colorHex) : {
          red: item.dominantColor.red,
          green: item.dominantColor.green,
          blue: item.dominantColor.blue,
          alpha: item.dominantColor.alpha,
        },
      })
      onSaved(saved)
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e))
      setSaving(false)
    }
  }

  const level = warmthLevelFor(meta.meta, draft.warmthScore)

  return (
    <form className="form" onSubmit={submit} aria-label="编辑单品">
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
      <div className="form-actions">
        <button type="button" className="button" onClick={onCancel}>
          取消
        </button>
        <button type="submit" className="button button-primary" disabled={saving}>
          保存
        </button>
      </div>
    </form>
  )
}
