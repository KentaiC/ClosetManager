import { useState } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { ItemCard } from '../wardrobe/ItemCard'

/** 高级筛选，对应 App 的 WardrobeSearchView：场景、主色、防水、过去 N 天未穿交叉筛选。 */
export function SearchPage() {
  const meta = useMeta()
  const { version } = useDataVersion()
  const [scenario, setScenario] = useState('')
  const [color, setColor] = useState('')
  const [waterproof, setWaterproof] = useState(false)
  const [unworn, setUnworn] = useState(false)
  const unwornDays = meta.meta.rules.unwornDays
  const results = useResource(
    () => api.search({ scenario: scenario || undefined, colorCategory: color || undefined, waterproof, unwornDays: unworn ? unwornDays : undefined }),
    [scenario, color, waterproof, unworn, version],
  )

  function reset() {
    setScenario('')
    setColor('')
    setWaterproof(false)
    setUnworn(false)
  }

  return (
    <section className="page">
      <div className="page-heading">
        <h1 className="page-title">高级筛选</h1>
        <button type="button" className="button" onClick={reset}>重置</button>
      </div>
      <div className="panel form">
        <label className="form-row">
          <span>场景</span>
          <select value={scenario} onChange={(e) => setScenario(e.target.value)}>
            <option value="">全部</option>
            {meta.meta.scenarios.map((o) => <option key={o.value} value={o.value}>{o.displayName}</option>)}
          </select>
        </label>
        <label className="form-row">
          <span>主色</span>
          <select value={color} onChange={(e) => setColor(e.target.value)}>
            <option value="">全部</option>
            {meta.meta.colorCategories.map((o) => <option key={o.value} value={o.value}>{o.displayName}</option>)}
          </select>
        </label>
        <label className="toggle">
          <input type="checkbox" checked={waterproof} onChange={(e) => setWaterproof(e.target.checked)} />
          仅防水单品
        </label>
        <label className="toggle">
          <input type="checkbox" checked={unworn} onChange={(e) => setUnworn(e.target.checked)} />
          过去 {unwornDays} 天未穿过（吃灰单品）
        </label>
      </div>
      {results.error ? (
        <ErrorPanel error={results.error} onRetry={results.reload} />
      ) : !results.data ? (
        <Loading />
      ) : (
        <>
          <p className="muted" data-testid="result-count">共 {results.data.length} 件</p>
          {results.data.length === 0 ? (
            <EmptyState title="没有符合条件的单品" description="放宽筛选条件试试。" />
          ) : (
            <div className="gallery gallery-medium">
              {results.data.map((item) => <ItemCard key={item.id} item={item} compact={false} />)}
            </div>
          )}
        </>
      )}
    </section>
  )
}
