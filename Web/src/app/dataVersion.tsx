import { createContext, useCallback, useContext, useMemo, useState, type ReactNode } from 'react'

/**
 * 数据版本号：任何写操作成功后调用 invalidate，依赖它的页面重新加载。
 * 相当于 App 中 SwiftData 的 @Query 在数据变化后自动刷新。
 */
const DataVersionContext = createContext<{ version: number; invalidate: () => void }>({ version: 0, invalidate: () => {} })

export function DataVersionProvider({ children }: { children: ReactNode }) {
  const [version, setVersion] = useState(0)
  const invalidate = useCallback(() => setVersion((value) => value + 1), [])
  const value = useMemo(() => ({ version, invalidate }), [version, invalidate])
  return <DataVersionContext.Provider value={value}>{children}</DataVersionContext.Provider>
}

export function useDataVersion() {
  return useContext(DataVersionContext)
}
