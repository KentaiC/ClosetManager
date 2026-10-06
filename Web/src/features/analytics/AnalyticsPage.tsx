import type { ReactNode } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { ActivityHeatmap } from './ActivityHeatmap'
import { ColorTreemap } from './ColorTreemap'
import { swatchColor, tileTextColor } from './colors'

function Card({ title, subtitle, children }: { title: string; subtitle: string; children: ReactNode }) {
  return (
    <section className="panel chart-card" aria-label={title}>
      <h2 className="chart-title">{title}</h2>
      <p className="muted chart-subtitle">{subtitle}</p>
      {children}
    </section>
  )
}

function Placeholder({ text }: { text: string }) {
  return <p className="muted center chart-placeholder">{text}</p>
}

/** 横向条形图，对应 App 看板中的 BarMark 图表。 */
function BarChart({ rows, label }: { rows: { key: string; label: string; count: number; color?: string }[]; label: string }) {
  const max = Math.max(...rows.map((row) => row.count), 1)
  return (
    <ul className="bar-chart" aria-label={label}>
      {rows.map((row) => (
        <li key={row.key} className="bar-row">
          <span className="bar-label">{row.label}</span>
          <span className="bar-track">
            <span className="bar" style={{ width: `${(row.count / max) * 100}%`, backgroundColor: row.color }} />
          </span>
          <span className="bar-value">{row.count}</span>
        </li>
      ))}
    </ul>
  )
}

/** 衣橱数据看板，对应 App 的 AnalyticsDashboardView。统计在服务端由共享核心计算，不含任何价格字段。 */
export function AnalyticsPage() {
  const meta = useMeta()
  const { version } = useDataVersion()
  const analytics = useResource(() => api.analytics(), [version])

  if (analytics.error) return <ErrorPanel error={analytics.error} onRetry={analytics.reload} />
  if (!analytics.data) return <Loading />
  const data = analytics.data
  const activity = new Map(data.dailyActivity.map((day) => [day.date, day.count]))

  return (
    <section className="page">
      <h1 className="page-title">看板</h1>
      <div className="chart-grid">
        <Card title="衣橱库存透视" subtitle="各分类件数">
          {data.inventory.length === 0 ? (
            <Placeholder text="衣橱还没有单品" />
          ) : (
            <BarChart
              label="各分类件数"
              rows={data.inventory.map((row) => ({ key: row.category, label: meta.name('category', row.category), count: row.count }))}
            />
          )}
        </Card>
        <Card title="衣橱颜色占比" subtitle="色块面积代表该颜色的件数">
          {data.colorInventory.length === 0 ? (
            <Placeholder text="衣橱还没有单品" />
          ) : (
            <ColorTreemap
              tiles={data.colorInventory.map((row) => ({
                key: row.colorCategory,
                label: meta.name('colorCategory', row.colorCategory),
                count: row.count,
                fill: swatchColor(row.colorCategory),
                text: tileTextColor(row.colorCategory),
              }))}
            />
          )}
        </Card>
        <Card title="色彩偏好分析" subtitle="历史穿搭中最常穿的颜色">
          {data.colorFrequency.length === 0 ? (
            <Placeholder text="还没有穿搭记录" />
          ) : (
            <BarChart
              label="最常穿的颜色"
              rows={data.colorFrequency.map((row) => ({
                key: row.colorCategory,
                label: meta.name('colorCategory', row.colorCategory),
                count: row.count,
                color: swatchColor(row.colorCategory),
              }))}
            />
          )}
        </Card>
        <Card title="穿着活跃度" subtitle="每天的穿搭打卡频率（最近 16 周）">
          {activity.size === 0 ? <Placeholder text="还没有穿搭记录" /> : <ActivityHeatmap activity={activity} />}
        </Card>
      </div>
    </section>
  )
}
