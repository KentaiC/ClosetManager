import { createContext, useContext, type ReactNode } from 'react'
import type { ApiCapabilities } from '../api/types'

/** 服务端的图片处理能力，来自 /api/v1/health。页面据此显示或隐藏抠图、取色、相似检测等功能。 */
const CapabilitiesContext = createContext<ApiCapabilities>({
  backgroundRemoval: false,
  colorExtraction: false,
  formatConversion: false,
  similarityDetection: false,
})

export function CapabilitiesProvider({ value, children }: { value: ApiCapabilities; children: ReactNode }) {
  return <CapabilitiesContext.Provider value={value}>{children}</CapabilitiesContext.Provider>
}

export function useCapabilities(): ApiCapabilities {
  return useContext(CapabilitiesContext)
}
