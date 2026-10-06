import type { MetaOption } from '../api/types'

/** 单选胶囊组，对应 App 的 SelectableChip。 */
export function ChipSingle({
  label,
  options,
  value,
  onChange,
}: {
  label: string
  options: MetaOption[]
  value: string
  onChange: (value: string) => void
}) {
  return (
    <div className="chips chips-wrap" role="radiogroup" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          role="radio"
          aria-checked={value === option.value}
          className={`chip${value === option.value ? ' selected' : ''}`}
          onClick={() => onChange(option.value)}
        >
          {option.displayName}
        </button>
      ))}
    </div>
  )
}

/**
 * 多选胶囊组，对应 App 的 ChipMultiSelect。结果按选项顺序排列。
 * 放在带 legend 的 fieldset 中时不传 label，由 legend 命名，避免读屏重复朗读同一个名称。
 */
export function ChipMulti({
  label,
  options,
  values,
  onChange,
}: {
  label?: string
  options: MetaOption[]
  values: string[]
  onChange: (values: string[]) => void
}) {
  function toggle(value: string) {
    const next = values.includes(value) ? values.filter((entry) => entry !== value) : [...values, value]
    onChange(options.map((option) => option.value).filter((entry) => next.includes(entry)))
  }
  return (
    <div className="chips chips-wrap" role="group" aria-label={label}>
      {options.map((option) => (
        <button
          key={option.value}
          type="button"
          aria-pressed={values.includes(option.value)}
          className={`chip${values.includes(option.value) ? ' selected' : ''}`}
          onClick={() => toggle(option.value)}
        >
          {option.displayName}
        </button>
      ))}
    </div>
  )
}
