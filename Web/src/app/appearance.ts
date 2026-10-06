// 外观偏好，对应 App 设置页的强调色、外观模式与卡片圆角。
// 与 App 一样只属于当前设备，这里保存在当前浏览器的 localStorage，键名沿用 App 的 @AppStorage 键。

export type AccentChoice = 'purple' | 'blue' | 'teal' | 'green' | 'orange' | 'pink' | 'red'
export type AppearanceMode = 'system' | 'light' | 'dark'

export interface Appearance {
  accent: AccentChoice
  mode: AppearanceMode
  cornerRadius: number
}

/** 选项与 App 的 AccentChoice、AppearanceMode 一致，颜色取 iOS 系统色。 */
export const ACCENTS: { value: AccentChoice; label: string; color: string }[] = [
  { value: 'purple', label: '紫色', color: '#AF52DE' },
  { value: 'blue', label: '蓝色', color: '#007AFF' },
  { value: 'teal', label: '青色', color: '#30B0C7' },
  { value: 'green', label: '绿色', color: '#34C759' },
  { value: 'orange', label: '橙色', color: '#FF9500' },
  { value: 'pink', label: '粉色', color: '#FF2D55' },
  { value: 'red', label: '红色', color: '#FF3B30' },
]

export const MODES: { value: AppearanceMode; label: string }[] = [
  { value: 'system', label: '跟随系统' },
  { value: 'light', label: '浅色' },
  { value: 'dark', label: '深色' },
]

export const DEFAULT_APPEARANCE: Appearance = { accent: 'purple', mode: 'system', cornerRadius: 16 }

const KEYS = { accent: 'ui.accent', mode: 'ui.appearance', cornerRadius: 'ui.cornerRadius' }

function read(key: string): string | null {
  try {
    return window.localStorage.getItem(key)
  } catch {
    return null
  }
}

export function loadAppearance(): Appearance {
  const accent = read(KEYS.accent)
  const mode = read(KEYS.mode)
  const radius = Number(read(KEYS.cornerRadius))
  return {
    accent: ACCENTS.some((option) => option.value === accent) ? (accent as AccentChoice) : DEFAULT_APPEARANCE.accent,
    mode: MODES.some((option) => option.value === mode) ? (mode as AppearanceMode) : DEFAULT_APPEARANCE.mode,
    cornerRadius: Number.isFinite(radius) && radius >= 0 && radius <= 28 && read(KEYS.cornerRadius) !== null ? radius : DEFAULT_APPEARANCE.cornerRadius,
  }
}

export function saveAppearance(appearance: Appearance): void {
  try {
    window.localStorage.setItem(KEYS.accent, appearance.accent)
    window.localStorage.setItem(KEYS.mode, appearance.mode)
    window.localStorage.setItem(KEYS.cornerRadius, String(appearance.cornerRadius))
  } catch {
    // 偏好只是便利设置，写入失败时忽略。
  }
}

/** 通过 CSS 变量与 data-theme 属性应用外观；不使用内联 style 标签，符合 CSP。 */
export function applyAppearance(appearance: Appearance, root: HTMLElement = document.documentElement): void {
  const accent = ACCENTS.find((option) => option.value === appearance.accent) ?? ACCENTS[0]!
  root.style.setProperty('--accent', accent.color)
  root.style.setProperty('--radius', `${appearance.cornerRadius}px`)
  if (appearance.mode === 'system') delete root.dataset.theme
  else root.dataset.theme = appearance.mode
}
