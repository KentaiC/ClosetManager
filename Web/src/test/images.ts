// 图片上传与处理的响应样例，字段与服务端 APIUploadedImage、APIProcessedImage 一致。
import type { ApiProcessedImage, ApiUploadedImage } from '../api/types'

export const ORIGINAL_SHA = 'a'.repeat(64)
export const CUTOUT_SHA = 'b'.repeat(64)

export function uploaded(sha256: string, format = 'jpeg', displayable = true): ApiUploadedImage {
  return {
    sha256,
    format,
    byteCount: 1234,
    width: 400,
    height: 300,
    displayable,
    url: `/api/v1/images/${sha256}`,
    thumbnailUrl: `/api/v1/images/${sha256}?variant=thumbnail`,
  }
}

/** Linux 上的处理结果：不抠图、不取色。 */
export const linuxProcessed: ApiProcessedImage = { original: uploaded(ORIGINAL_SHA) }

/** macOS 上的处理结果：有抠图结果与主辅色。 */
export const macProcessed: ApiProcessedImage = {
  original: uploaded(ORIGINAL_SHA),
  processed: { ...uploaded(CUTOUT_SHA, 'png'), width: undefined, height: undefined },
  dominantColor: { red: 0.1, green: 0.2, blue: 0.7, alpha: 1, hex: '#1A33B3', name: '蓝色' },
  secondaryColor: { red: 0.9, green: 0.9, blue: 0.9, alpha: 1, hex: '#E6E6E6', name: '浅灰' },
}

export function imageFile(name = 'tee.jpg', type = 'image/jpeg'): File {
  return new File([new Uint8Array([0xff, 0xd8, 0xff, 0xd9])], name, { type })
}
