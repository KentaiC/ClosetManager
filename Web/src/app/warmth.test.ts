import { describe, expect, it } from 'vitest'
import { metaFixture } from '../test/fixtures'
import { seasonsForScore, warmthLevelFor } from './warmth'

describe('warmth helpers', () => {
  it('maps scores to levels using the server score ranges', () => {
    expect(warmthLevelFor(metaFixture, 100)).toBe('frigid')
    expect(warmthLevelFor(metaFixture, 85)).toBe('frigid')
    expect(warmthLevelFor(metaFixture, 84)).toBe('cold')
    expect(warmthLevelFor(metaFixture, 17)).toBe('warm')
    expect(warmthLevelFor(metaFixture, 16)).toBe('hot')
    expect(warmthLevelFor(metaFixture, 1)).toBe('hot')
    expect(warmthLevelFor(metaFixture, 0)).toBeUndefined()
  })

  it('derives seasons in season order from the level', () => {
    expect(seasonsForScore(metaFixture, 20)).toEqual(['spring', 'summer'])
    expect(seasonsForScore(metaFixture, 70)).toEqual(['autumn', 'winter'])
    expect(seasonsForScore(metaFixture, 0)).toEqual([])
  })
})
