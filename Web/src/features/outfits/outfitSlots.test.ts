import { describe, expect, it } from 'vitest'
import { draftsFixture, fixtureItem, metaFixture } from '../../test/fixtures'
import { isManualComplete, MANUAL_SLOT_CATEGORIES, manualMembers, memberLabels, toMembers } from './outfitSlots'

const categoryName = (category: string) => `分类:${category}`
const top = fixtureItem('白色T恤')
const bottom = fixtureItem('下装')
const shoes = fixtureItem('防水靴')
const required = metaFixture.categories.filter((category) => category.isRequiredInOutfit).map((category) => category.value)

describe('memberLabels', () => {
  it('labels server drafts like the App draft card', () => {
    expect(memberLabels(draftsFixture.drafts[0]!.members, categoryName)).toEqual(['上装', '下装', '鞋子'])
  })

  it('calls the top 打底 when a mid layer is present', () => {
    const members = ['outerwear', 'midLayer', 'top', 'bottom', 'socks', 'shoes', 'accessory'].map((slot) => ({ slot, item: top }))
    expect(memberLabels(members, categoryName)).toEqual(['外套', '中层', '打底', '下装', '袜子', '鞋子', '配饰'])
  })

  it('falls back to the category name when a member has no slot', () => {
    expect(memberLabels([{ item: shoes }], categoryName)).toEqual(['分类:shoes'])
  })
})

describe('toMembers', () => {
  it('keeps slots and omits missing ones', () => {
    expect(toMembers([{ slot: 'top', item: top }, { item: shoes }])).toEqual([{ itemId: top.id, slot: 'top' }, { itemId: shoes.id }])
  })
})

describe('manual builder rules', () => {
  it('uses the App slot order and treats slot values as category values', () => {
    expect(MANUAL_SLOT_CATEGORIES).toEqual(['outerwear', 'top', 'bottom', 'socks', 'shoes', 'accessory'])
    for (const slot of MANUAL_SLOT_CATEGORIES) expect(metaFixture.categories.map((category) => category.value)).toContain(slot)
  })

  it('requires top, bottom and shoes from server metadata', () => {
    expect(required).toEqual(['top', 'bottom', 'shoes'])
    expect(isManualComplete({ top, shoes }, required)).toBe(false)
    expect(isManualComplete({ top, bottom, shoes, outerwear: undefined }, required)).toBe(true)
  })

  it('lists picks in draft order regardless of the order they were picked', () => {
    const members = manualMembers({ shoes, bottom, top })
    expect(members.map((member) => member.slot)).toEqual(['top', 'bottom', 'shoes'])
    expect(members.map((member) => member.item.id)).toEqual([top.id, bottom.id, shoes.id])
  })
})
