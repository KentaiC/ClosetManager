import { api } from './api/client'
import { useResource } from './api/useResource'
import { ErrorBoundary, ErrorPanel, Loading } from './app/Feedback'
import { CapabilitiesProvider } from './app/capabilities'
import { DataVersionProvider } from './app/dataVersion'
import { MetaLookup, MetaProvider } from './app/meta'
import { Link, useRoute, type Route } from './app/router'
import { ToastProvider } from './app/toast'
import { AnalyticsPage } from './features/analytics/AnalyticsPage'
import { CalendarPage } from './features/calendar/CalendarPage'
import { BatchImportPage } from './features/items/BatchImportPage'
import { NewItemPage } from './features/items/NewItemPage'
import { SimilarItemsPage } from './features/items/SimilarItemsPage'
import { LaundryPage } from './features/laundry/LaundryPage'
import { NotFoundPage } from './features/notFound/NotFoundPage'
import { OutfitsPage } from './features/outfits/OutfitsPage'
import { SearchPage } from './features/search/SearchPage'
import { SettingsPage } from './features/settings/SettingsPage'
import { TravelPage } from './features/travel/TravelPage'
import { ItemDetailPage } from './features/wardrobe/ItemDetailPage'
import { WardrobePage } from './features/wardrobe/WardrobePage'

/** 主导航，与 App 底部的五个 Tab 一一对应。 */
const TABS: { to: string; label: string; matches: Route['name'][] }[] = [
  { to: '/', label: '衣橱', matches: ['wardrobe', 'item', 'search', 'newItem', 'batchImport'] },
  { to: '/laundry', label: '洗衣房', matches: ['laundry'] },
  { to: '/outfits', label: '穿搭', matches: ['outfits'] },
  { to: '/calendar', label: '日历', matches: ['calendar'] },
  { to: '/analytics', label: '看板', matches: ['analytics'] },
]

/** 从设置页进入的页面，导航时高亮「设置」。 */
const SETTINGS_ROUTES: Route['name'][] = ['settings', 'travel', 'similar']

function Page({ route }: { route: Route }) {
  switch (route.name) {
    case 'wardrobe':
      return <WardrobePage />
    case 'item':
      return <ItemDetailPage id={route.id} />
    case 'laundry':
      return <LaundryPage />
    case 'outfits':
      return <OutfitsPage />
    case 'calendar':
      return <CalendarPage />
    case 'analytics':
      return <AnalyticsPage />
    case 'settings':
      return <SettingsPage />
    case 'search':
      return <SearchPage />
    case 'travel':
      return <TravelPage />
    case 'newItem':
      return <NewItemPage />
    case 'batchImport':
      return <BatchImportPage />
    case 'similar':
      return <SimilarItemsPage />
    case 'notFound':
      return <NotFoundPage />
  }
}

export function App() {
  const route = useRoute()
  const meta = useResource(
    () => Promise.all([api.meta(), api.health()]).then(([value, health]) => ({ lookup: new MetaLookup(value), capabilities: health.capabilities })),
    [],
  )

  return (
    <DataVersionProvider>
      <ToastProvider>
        <div className="app">
          <header className="app-header">
            <Link to="/" className="brand">
              Closet Manager
            </Link>
            <nav className="tabs" aria-label="主导航">
              {TABS.map((tab) => (
                <Link
                  key={tab.to}
                  to={tab.to}
                  className={`tab${tab.matches.includes(route.name) ? ' active' : ''}`}
                  aria-current={tab.matches.includes(route.name) ? 'page' : undefined}
                >
                  {tab.label}
                </Link>
              ))}
            </nav>
            <Link to="/settings" className={`settings-link${SETTINGS_ROUTES.includes(route.name) ? ' active' : ''}`} aria-label="设置">
              设置
            </Link>
          </header>
          <main className="app-main">
            {meta.error ? (
              <ErrorPanel error={meta.error} onRetry={meta.reload} />
            ) : !meta.data ? (
              <Loading label="正在连接本地服务…" />
            ) : (
              <MetaProvider value={meta.data.lookup}>
                <CapabilitiesProvider value={meta.data.capabilities}>
                  <ErrorBoundary key={route.name === 'item' ? `item-${route.id}` : route.name}>
                    <Page route={route} />
                  </ErrorBoundary>
                </CapabilitiesProvider>
              </MetaProvider>
            )}
          </main>
        </div>
      </ToastProvider>
    </DataVersionProvider>
  )
}
