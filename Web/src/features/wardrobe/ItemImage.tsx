import type { ApiItem } from '../../api/types'

/**
 * 单品图片：列表使用缩略图，详情使用展示图。
 * 浏览器无法直接显示、服务端也不能转换的格式（如 Linux 上的 HEIC）显示占位图标。
 */
export function ItemImage({ item, className, variant = 'thumbnail' }: { item: ApiItem; className?: string; variant?: 'thumbnail' | 'display' }) {
  const image = item.images.display
  const url = variant === 'thumbnail' ? (item.images.thumbnailUrl ?? image?.url) : image?.url
  return (
    <div className={`item-image ${className ?? ''}`}>
      {image?.displayable && url ? (
        <img src={url} alt={item.title} loading="lazy" decoding="async" />
      ) : (
        <span className="item-image-placeholder" role="img" aria-label={image ? '此格式需转码后才能显示' : '没有图片'}>
          {image ? 'HEIC' : '无图'}
        </span>
      )}
    </div>
  )
}
