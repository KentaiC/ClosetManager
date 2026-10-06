import { dateKey, firstDayOfWeek, heatmapDays, intensity } from './heatmap'

/** GitHub 贡献图风格的穿着活跃度热力图，对应 App 的 ActivityHeatmapView：每列一周，最近 16 周。 */
export function ActivityHeatmap({ activity, today = new Date(), weeks = 16 }: { activity: Map<string, number>; today?: Date; weeks?: number }) {
  const firstDay = firstDayOfWeek(typeof navigator === 'undefined' ? undefined : navigator.language)
  const days = heatmapDays(today, weeks, firstDay)
  return (
    <div className="heatmap-wrap">
      <div className="heatmap" role="list" aria-label={`最近 ${weeks} 周的穿着次数`}>
        {days.map((day) => {
          const key = dateKey(day)
          const count = activity.get(key) ?? 0
          return (
            <span
              key={key}
              role="listitem"
              className={`heat heat-${intensity(count)}`}
              title={`${key}：${count} 次`}
              aria-label={`${key} ${count} 次`}
              data-date={key}
            />
          )
        })}
      </div>
      <div className="heatmap-legend" aria-hidden="true">
        <span>少</span>
        {[0, 1, 2, 3].map((level) => (
          <span key={level} className={`heat heat-${level}`} />
        ))}
        <span>多</span>
      </div>
    </div>
  )
}
