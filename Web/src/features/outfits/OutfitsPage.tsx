import { useState } from 'react'
import { FavoritesList } from './FavoritesList'
import { ManualBuilder } from './ManualBuilder'
import { OutfitGenerator } from './OutfitGenerator'

const MODES = [
  { value: 'generate', label: '智能生成' },
  { value: 'favorites', label: '收藏夹' },
  { value: 'manual', label: '自由拼搭' },
] as const

type Mode = (typeof MODES)[number]['value']

/** 「穿搭」页，对应 App 的 OutfitHomeView：智能生成、收藏夹、自由拼搭三个子页。 */
export function OutfitsPage() {
  const [mode, setMode] = useState<Mode>('generate')
  return (
    <section className="page">
      <h1 className="page-title">穿搭</h1>
      <div className="segmented segmented-full" role="tablist" aria-label="模式">
        {MODES.map((option) => (
          <button
            key={option.value}
            type="button"
            role="tab"
            aria-selected={mode === option.value}
            className={mode === option.value ? 'selected' : ''}
            onClick={() => setMode(option.value)}
          >
            {option.label}
          </button>
        ))}
      </div>
      {mode === 'generate' ? <OutfitGenerator /> : mode === 'favorites' ? <FavoritesList /> : <ManualBuilder />}
    </section>
  )
}
