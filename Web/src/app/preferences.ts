// 仅属于当前浏览器的界面偏好，保存在 localStorage。读写失败时退回默认值。

export type GallerySize = 'large' | 'medium' | 'small'

const GALLERY_SIZE_KEY = 'galleryItemSize'

export function loadGallerySize(): GallerySize {
  try {
    const value = window.localStorage.getItem(GALLERY_SIZE_KEY)
    if (value === 'large' || value === 'medium' || value === 'small') return value
  } catch {
    // 存储不可用时使用默认值。
  }
  return 'medium'
}

export function saveGallerySize(size: GallerySize): void {
  try {
    window.localStorage.setItem(GALLERY_SIZE_KEY, size)
  } catch {
    // 忽略：偏好只是便利设置。
  }
}
