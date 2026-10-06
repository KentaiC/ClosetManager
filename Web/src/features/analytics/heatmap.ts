// 穿着活跃度热力图的日期计算，移植自 App 的 ActivityHeatmapView。
// 日期一律使用本地时区的自然日，与服务端按本机日历汇总的 YYYY-MM-DD 键一致。

function startOfDay(date: Date): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate())
}

function addDays(date: Date, days: number): Date {
  return new Date(date.getFullYear(), date.getMonth(), date.getDate() + days)
}

/** 本地日期键，格式 YYYY-MM-DD。 */
export function dateKey(date: Date): string {
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${date.getFullYear()}-${month}-${day}`
}

/**
 * 从对齐到周首的起点到今天的全部日期，每 7 天为一列。
 * firstDay 为一周的第一天，取值同 Date.getDay：0 为星期日，1 为星期一。
 */
export function heatmapDays(today: Date, weeks: number, firstDay: number): Date[] {
  const end = startOfDay(today)
  const rawStart = addDays(end, -(weeks * 7 - 1))
  const start = addDays(rawStart, -((rawStart.getDay() - firstDay + 7) % 7))
  const days: Date[] = []
  for (let cursor = start; cursor <= end; cursor = addDays(cursor, 1)) days.push(cursor)
  return days
}

/** 强度档位，与 App 相同：0 次、1 次、2 次、3 次及以上。 */
export function intensity(count: number): 0 | 1 | 2 | 3 {
  if (count <= 0) return 0
  if (count === 1) return 1
  if (count === 2) return 2
  return 3
}

/**
 * 当前语言区域的一周第一天，取值同 Date.getDay。
 * App 使用设备日历 Calendar.current，这里对应浏览器语言区域的周信息。
 * 浏览器不提供周信息时使用星期日。
 */
export function firstDayOfWeek(locale: string | undefined): number {
  try {
    const value = new Intl.Locale(locale ?? 'und') as Intl.Locale & {
      getWeekInfo?: () => { firstDay: number }
      weekInfo?: { firstDay: number }
    }
    const info = value.getWeekInfo?.() ?? value.weekInfo
    if (info && Number.isInteger(info.firstDay) && info.firstDay >= 1 && info.firstDay <= 7) return info.firstDay % 7
  } catch {
    // 语言标签无效时使用默认值。
  }
  return 0
}
