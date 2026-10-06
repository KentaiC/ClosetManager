import { useCallback, useEffect, useRef, useState } from 'react'
import { api } from '../../api/client'
import type { ApiColor, ApiUploadedImage } from '../../api/types'

export type IngestResult = {
  original: ApiUploadedImage
  processed?: ApiUploadedImage
  dominantColor?: ApiColor
  secondaryColor?: ApiColor
  failure?: string
}

export type IngestState =
  | { phase: 'idle' }
  | { phase: 'uploading' | 'processing' }
  | ({ phase: 'done' } & IngestResult)
  | { phase: 'error'; message: string }

/**
 * 上传一张图片并抠图取色，对应 App 的 `ItemDraftModel.ingest`。
 * 新的图片或组件卸载会让进行中的旧结果作废，快速跳过时不会被旧图片覆盖（审计 M-11）。
 */
export function useImageIngest() {
  const [state, setState] = useState<IngestState>({ phase: 'idle' })
  const generation = useRef(0)

  useEffect(
    () => () => {
      generation.current += 1
    },
    [],
  )

  const ingest = useCallback(async (file: File): Promise<IngestResult | null> => {
    const current = ++generation.current
    setState({ phase: 'uploading' })
    try {
      const original = await api.uploadImage(file)
      if (current !== generation.current) return null
      setState({ phase: 'processing' })
      const processed = await api.processImage(original.sha256)
      if (current !== generation.current) return null
      const result: IngestResult = {
        original: processed.original,
        processed: processed.processed,
        dominantColor: processed.dominantColor,
        secondaryColor: processed.secondaryColor,
        failure: processed.failure,
      }
      setState({ phase: 'done', ...result })
      return result
    } catch (e) {
      if (current === generation.current) setState({ phase: 'error', message: e instanceof Error ? e.message : String(e) })
      return null
    }
  }, [])

  return { state, ingest }
}
