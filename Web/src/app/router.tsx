import { useSyncExternalStore, type AnchorHTMLAttributes, type MouseEvent } from 'react'

/** 应用内的页面。 */
export type Route =
  | { name: 'wardrobe' }
  | { name: 'item'; id: string }
  | { name: 'newItem' }
  | { name: 'batchImport' }
  | { name: 'laundry' }
  | { name: 'outfits' }
  | { name: 'calendar' }
  | { name: 'analytics' }
  | { name: 'settings' }
  | { name: 'search' }
  | { name: 'travel' }
  | { name: 'notFound' }

export function parseRoute(pathname: string): Route {
  const path = pathname.replace(/\/+$/, '') || '/'
  switch (path) {
    case '/':
      return { name: 'wardrobe' }
    case '/laundry':
      return { name: 'laundry' }
    case '/outfits':
      return { name: 'outfits' }
    case '/calendar':
      return { name: 'calendar' }
    case '/analytics':
      return { name: 'analytics' }
    case '/settings':
      return { name: 'settings' }
    case '/search':
      return { name: 'search' }
    case '/travel':
      return { name: 'travel' }
    case '/items/new':
      return { name: 'newItem' }
    case '/items/batch':
      return { name: 'batchImport' }
  }
  const item = /^\/items\/([0-9A-Fa-f-]{36})$/.exec(path)
  if (item?.[1]) return { name: 'item', id: item[1] }
  return { name: 'notFound' }
}

const NAVIGATE_EVENT = 'closet:navigate'

function subscribe(callback: () => void): () => void {
  window.addEventListener('popstate', callback)
  window.addEventListener(NAVIGATE_EVENT, callback)
  return () => {
    window.removeEventListener('popstate', callback)
    window.removeEventListener(NAVIGATE_EVENT, callback)
  }
}

export function navigate(to: string): void {
  if (to === window.location.pathname + window.location.search) return
  window.history.pushState(null, '', to)
  window.dispatchEvent(new Event(NAVIGATE_EVENT))
  window.scrollTo?.(0, 0)
}

/** 当前路由；地址变化时组件自动刷新。 */
export function useRoute(): Route {
  const pathname = useSyncExternalStore(subscribe, () => window.location.pathname)
  return parseRoute(pathname)
}

/** 应用内链接：普通点击走前端路由，带修饰键的点击保留浏览器默认行为。 */
export function Link({ to, onClick, ...rest }: AnchorHTMLAttributes<HTMLAnchorElement> & { to: string }) {
  function handle(event: MouseEvent<HTMLAnchorElement>) {
    onClick?.(event)
    if (event.defaultPrevented || event.button !== 0 || event.metaKey || event.ctrlKey || event.shiftKey || event.altKey) return
    event.preventDefault()
    navigate(to)
  }
  return <a href={to} onClick={handle} {...rest} />
}
