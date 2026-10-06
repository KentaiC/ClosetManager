import { describe, expect, it } from 'vitest'
import { metaFixture } from '../test/fixtures'
import { MetaLookup } from './meta'

describe('MetaLookup', () => {
  const lookup = new MetaLookup(metaFixture)

  it('resolves display names from the server metadata', () => {
    expect(lookup.name('category', 'socks')).toBe('袜子')
    expect(lookup.name('subtype', 'trenchCoat')).toBe('风衣')
    expect(lookup.name('scenario', 'work')).toBe('通勤')
    expect(lookup.name('status', 'inLuggage')).toBe('在行李箱')
    expect(lookup.name('warmthLevel', 'frigid')).toBe('严寒')
    expect(lookup.name('season', 'autumn')).toBe('秋')
  })

  it('falls back to the raw value and handles empty input', () => {
    expect(lookup.name('category', 'unknownValue')).toBe('unknownValue')
    expect(lookup.name('subtype', null)).toBe('')
  })
})
