import { describe, expect, it } from 'vitest'
import type { ApiItem } from '../../api/types'
import { itemsFixture } from '../../test/fixtures'
import { visibleGalleryItems } from './galleryFilter'

function item(status: string, category = 'top'): ApiItem {
  return { ...itemsFixture[0]!, id: `${status}-${category}`, status, category }
}

describe('visibleGalleryItems', () => {
  const items = [item('inWardrobe'), item('inLaundry'), item('inLuggage'), item('inWardrobe', 'shoes')]

  it('hides laundry by default and luggage always', () => {
    expect(visibleGalleryItems(items, { showLaundry: false }).map((i) => i.id)).toEqual(['inWardrobe-top', 'inWardrobe-shoes'])
  })

  it('shows laundry only when the toggle is on', () => {
    expect(visibleGalleryItems(items, { showLaundry: true }).map((i) => i.id)).toEqual([
      'inWardrobe-top',
      'inLaundry-top',
      'inWardrobe-shoes',
    ])
  })

  it('filters by category after status isolation', () => {
    expect(visibleGalleryItems(items, { showLaundry: true, category: 'shoes' }).map((i) => i.id)).toEqual(['inWardrobe-shoes'])
  })

  it('keeps server order', () => {
    const ordered = visibleGalleryItems(itemsFixture, { showLaundry: true })
    expect(ordered.map((i) => i.status)).toEqual(['inLaundry', 'inWardrobe'])
  })
})
