import { describe, expect, it } from 'vitest'
import { applyAppearance, DEFAULT_APPEARANCE, loadAppearance, saveAppearance } from './appearance'

describe('appearance preferences', () => {
  it('uses the App defaults when nothing is stored', () => {
    expect(loadAppearance()).toEqual(DEFAULT_APPEARANCE)
    expect(DEFAULT_APPEARANCE).toEqual({ accent: 'purple', mode: 'system', cornerRadius: 16 })
  })

  it('round-trips through the App storage keys', () => {
    saveAppearance({ accent: 'teal', mode: 'dark', cornerRadius: 0 })
    expect(window.localStorage.getItem('ui.accent')).toBe('teal')
    expect(window.localStorage.getItem('ui.appearance')).toBe('dark')
    expect(window.localStorage.getItem('ui.cornerRadius')).toBe('0')
    expect(loadAppearance()).toEqual({ accent: 'teal', mode: 'dark', cornerRadius: 0 })
  })

  it('ignores unknown or out-of-range stored values', () => {
    window.localStorage.setItem('ui.accent', 'gold')
    window.localStorage.setItem('ui.appearance', 'sepia')
    window.localStorage.setItem('ui.cornerRadius', '99')
    expect(loadAppearance()).toEqual(DEFAULT_APPEARANCE)
  })

  it('applies colours through CSS variables and data-theme', () => {
    const root = document.createElement('div')
    applyAppearance({ accent: 'blue', mode: 'light', cornerRadius: 8 }, root)
    expect(root.style.getPropertyValue('--accent')).toBe('#007AFF')
    expect(root.style.getPropertyValue('--radius')).toBe('8px')
    expect(root.dataset.theme).toBe('light')
    applyAppearance({ accent: 'blue', mode: 'system', cornerRadius: 8 }, root)
    expect(root.dataset.theme).toBeUndefined()
  })
})
