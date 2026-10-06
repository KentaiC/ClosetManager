import type { ApiMeta } from '../api/types'

/** 保暖度对应的档位，分数范围来自服务端元数据。 */
export function warmthLevelFor(meta: ApiMeta, score: number): string | undefined {
  return meta.warmthLevels.find((level) => score >= level.minScore && score <= level.maxScore)?.value
}

/** 由保暖度推导季节，与 App 的 deriveSeasonsIfNeeded 相同：取对应档位的季节，按季节顺序排列。 */
export function seasonsForScore(meta: ApiMeta, score: number): string[] {
  const level = meta.warmthLevels.find((entry) => entry.value === warmthLevelFor(meta, score))
  if (!level) return []
  return meta.seasons.map((season) => season.value).filter((season) => level.seasons.includes(season))
}
