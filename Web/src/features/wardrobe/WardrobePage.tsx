import { useMemo, useState } from 'react'
import { api } from '../../api/client'
import { useResource } from '../../api/useResource'
import { EmptyState, ErrorPanel, Loading } from '../../app/Feedback'
import { useDataVersion } from '../../app/dataVersion'
import { useMeta } from '../../app/meta'
import { loadGallerySize, saveGallerySize, type GallerySize } from '../../app/preferences'
import { Link } from '../../app/router'
import { ActiveOutfitPanel } from './ActiveOutfitPanel'
import { ItemCard } from './ItemCard'
import { visibleGalleryItems } from './galleryFilter'

const SIZE_LABELS: Record<GallerySize, string> = { large: '大', medium: '中', small: '小' }

/** 衣橱主页，对应 App 的 WardrobeGalleryView。 */
export function WardrobePage() {
  const meta = useMeta()
  const { version } = useDataVersion()
  const items = useResource(() => api.items(), [version])
  const [category, setCategory] = useState<string | undefined>(undefined)
  const [showLaundry, setShowLaundry] = useState(false)
  const [size, setSize] = useState<GallerySize>(loadGallerySize)

  const visible = useMemo(
    () => visibleGalleryItems(items.data ?? [], { category, showLaundry }),
    [items.data, category, showLaundry],
  )

  function changeSize(next: GallerySize) {
    setSize(next)
    saveGallerySize(next)
  }

  return (
    <section className="page">
      <h1 className="page-title">我的衣橱</h1>
      <ActiveOutfitPanel />

      <div className="toolbar">
        <div className="segmented" role="group" aria-label="视图大小">
          {(Object.keys(SIZE_LABELS) as GallerySize[]).map((value) => (
            <button
              key={value}
              type="button"
              className={value === size ? 'selected' : ''}
              aria-pressed={value === size}
              onClick={() => changeSize(value)}
            >
              {SIZE_LABELS[value]}
            </button>
          ))}
        </div>
        <label className="toggle">
          <input type="checkbox" checked={showLaundry} onChange={(event) => setShowLaundry(event.target.checked)} />
          显示洗衣袋内衣物
        </label>
        <Link to="/search" className="button">
          高级筛选
        </Link>
      </div>
      {showLaundry && <p className="notice">正在显示洗衣袋内衣物</p>}

      {items.error ? (
        <ErrorPanel error={items.error} onRetry={items.reload} />
      ) : items.loading && !items.data ? (
        <Loading />
      ) : (items.data ?? []).length === 0 ? (
        <EmptyState title="衣橱还是空的" description="可以先用 closet-server import 导入 App 的备份文件。" />
      ) : (
        <>
          <div className="chips" role="group" aria-label="分类">
            <button type="button" className={`chip${category === undefined ? ' selected' : ''}`} onClick={() => setCategory(undefined)}>
              全部
            </button>
            {meta.meta.categories.map((option) => (
              <button
                key={option.value}
                type="button"
                className={`chip${category === option.value ? ' selected' : ''}`}
                aria-pressed={category === option.value}
                onClick={() => setCategory(option.value)}
              >
                {option.displayName}
              </button>
            ))}
          </div>
          {visible.length === 0 ? (
            <EmptyState title="该分类下没有可显示的单品" description="换个分类试试。" />
          ) : (
            <div className={`gallery gallery-${size}`} data-testid="gallery">
              {visible.map((item) => (
                <ItemCard key={item.id} item={item} compact={size === 'small'} />
              ))}
            </div>
          )}
        </>
      )}
    </section>
  )
}
