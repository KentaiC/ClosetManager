// 颜色桶的展示色，与 App 看板的 swatchColor、textColor 对应。
// App 使用 SwiftUI 系统色，这里取这些系统色在浅色模式下的取值，仅用于图表着色。

const SWATCHES: Record<string, string> = {
  black: '#000000',
  white: '#EBEBEB',
  gray: '#8E8E93',
  beige: '#DED1B3',
  brown: '#A2845E',
  red: '#FF3B30',
  orange: '#FF9500',
  yellow: '#FFCC00',
  green: '#34C759',
  cyan: '#32ADE6',
  blue: '#007AFF',
  purple: '#AF52DE',
  pink: '#FF2D55',
  multicolor: '#999999',
}

/** 颜色桶的代表色。未知取值使用中性灰。 */
export function swatchColor(colorCategory: string): string {
  return SWATCHES[colorCategory] ?? '#999999'
}

const DARK_TEXT = new Set(['white', 'beige', 'yellow', 'gray', 'pink', 'cyan'])

/** 色块上的文字色：浅底用黑字，深底用白字。 */
export function tileTextColor(colorCategory: string): string {
  return DARK_TEXT.has(colorCategory) ? '#000000' : '#FFFFFF'
}
