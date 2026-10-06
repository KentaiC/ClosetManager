import { useCallback, useEffect, useState } from 'react'
import { ApiError } from './client'

export interface Resource<T> {
  data: T | undefined
  error: ApiError | undefined
  loading: boolean
  reload: () => void
}

/** 加载一个异步资源；依赖变化或调用 reload 时重新加载，并丢弃过期的响应。 */
export function useResource<T>(load: () => Promise<T>, deps: readonly unknown[]): Resource<T> {
  const [state, setState] = useState<{ data?: T; error?: ApiError; loading: boolean }>({ loading: true })
  const [generation, setGeneration] = useState(0)
  const reload = useCallback(() => setGeneration((value) => value + 1), [])

  useEffect(() => {
    let current = true
    setState((previous) => ({ data: previous.data, loading: true }))
    load().then(
      (data) => current && setState({ data, loading: false }),
      (error: unknown) =>
        current &&
        setState({
          loading: false,
          error: error instanceof ApiError ? error : new ApiError(0, 'unknown', String(error)),
        }),
    )
    return () => {
      current = false
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [...deps, generation])

  return { data: state.data, error: state.error, loading: state.loading, reload }
}
