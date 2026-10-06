import type { ApiItem } from '../../api/types'

/** 单品图片：浏览器无法直接显示的格式（如 HEIC）显示占位图标。 */
export function ItemImage({ item, className }: { item: ApiItem; className?: string }) {
  const image = item.images.display
  return (
    <div className={`item-image ${className ?? ''}`}>
      {image?.displayable ? (
        <img src={image.url} alt={item.title} loading="lazy" decoding="async" />
      ) : (
        <span className="item-image-placeholder" role="img" aria-label={image ? '此格式需转码后才能显示' : '没有图片'}>
          {image ? 'HEIC' : '无图'}
        </span>
      )}
    </div>
  )
}
