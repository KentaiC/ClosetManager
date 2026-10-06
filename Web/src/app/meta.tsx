import { createContext, useContext, type ReactNode } from 'react'
import type { ApiMeta, MetaOption } from '../api/types'

/** 枚举原始值到中文名称的查找表，数据来自服务端的 /api/v1/meta。 */
export class MetaLookup {
  readonly meta: ApiMeta
  private readonly names = new Map<string, string>()

  constructor(meta: ApiMeta) {
    this.meta = meta
    const add = (kind: string, options: MetaOption[]) => {
      for (const option of options) this.names.set(`${kind}:${option.value}`, option.displayName)
    }
    add('category', meta.categories)
    add('subtype', meta.categories.flatMap((category) => category.subtypes))
    add('scenario', meta.scenarios)
    add('status', meta.statuses)
    add('warmthLevel', meta.warmthLevels)
    add('season', meta.seasons)
    add('colorCategory', meta.colorCategories)
    add('outfitSource', meta.outfitSources)
    add('gender', meta.genders)
  }

  /** 查不到时返回原始值，便于发现前后端不一致。 */
  name(kind: 'category' | 'subtype' | 'scenario' | 'status' | 'warmthLevel' | 'season' | 'colorCategory' | 'outfitSource' | 'gender', value: string | null | undefined): string {
    if (!value) return ''
    return this.names.get(`${kind}:${value}`) ?? value
  }
}

const MetaContext = createContext<MetaLookup | null>(null)

export function MetaProvider({ value, children }: { value: MetaLookup; children: ReactNode }) {
  return <MetaContext.Provider value={value}>{children}</MetaContext.Provider>
}

export function useMeta(): MetaLookup {
  const lookup = useContext(MetaContext)
  if (!lookup) throw new Error('useMeta must be used inside MetaProvider')
  return lookup
}
