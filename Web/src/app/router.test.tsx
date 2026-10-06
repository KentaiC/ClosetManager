import { act, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { describe, expect, it } from 'vitest'
import { Link, navigate, parseRoute, useRoute } from './router'

describe('parseRoute', () => {
  it('maps every page', () => {
    expect(parseRoute('/')).toEqual({ name: 'wardrobe' })
    expect(parseRoute('/laundry/')).toEqual({ name: 'laundry' })
    expect(parseRoute('/outfits')).toEqual({ name: 'outfits' })
    expect(parseRoute('/calendar')).toEqual({ name: 'calendar' })
    expect(parseRoute('/analytics')).toEqual({ name: 'analytics' })
    expect(parseRoute('/settings')).toEqual({ name: 'settings' })
    expect(parseRoute('/search')).toEqual({ name: 'search' })
    expect(parseRoute('/travel')).toEqual({ name: 'travel' })
    expect(parseRoute('/items/new')).toEqual({ name: 'newItem' })
    expect(parseRoute('/items/batch')).toEqual({ name: 'batchImport' })
    expect(parseRoute('/similar')).toEqual({ name: 'similar' })
    expect(parseRoute('/items/7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E')).toEqual({
      name: 'item',
      id: '7A2C1D9E-3B4F-4C5A-9D6E-1F2A3B4C5D6E',
    })
  })

  it('rejects malformed paths', () => {
    expect(parseRoute('/items/../../etc')).toEqual({ name: 'notFound' })
    expect(parseRoute('/items/abc')).toEqual({ name: 'notFound' })
    expect(parseRoute('/nope')).toEqual({ name: 'notFound' })
  })
})

function CurrentRoute() {
  return <span data-testid="route">{useRoute().name}</span>
}

describe('navigation', () => {
  it('updates subscribers on link click, navigate and back', async () => {
    render(
      <>
        <CurrentRoute />
        <Link to="/laundry">洗衣房</Link>
      </>,
    )
    expect(screen.getByTestId('route')).toHaveTextContent('wardrobe')
    await userEvent.click(screen.getByText('洗衣房'))
    expect(screen.getByTestId('route')).toHaveTextContent('laundry')
    expect(window.location.pathname).toBe('/laundry')
    act(() => navigate('/calendar'))
    expect(screen.getByTestId('route')).toHaveTextContent('calendar')
    act(() => {
      window.history.back()
    })
    await screen.findByText('laundry')
  })
})
