import { Component, type ErrorInfo, type ReactNode } from 'react'
import type { ApiError } from '../api/client'

export function Loading({ label = '正在加载…' }: { label?: string }) {
  return (
    <div className="feedback" role="status" aria-live="polite">
      <span className="spinner" aria-hidden="true" />
      {label}
    </div>
  )
}

export function ErrorPanel({ error, onRetry }: { error: ApiError; onRetry?: () => void }) {
  return (
    <div className="feedback feedback-error" role="alert">
      <p>{error.message}</p>
      {onRetry && (
        <button type="button" className="button" onClick={onRetry}>
          重试
        </button>
      )}
    </div>
  )
}

export function EmptyState({ title, description, children }: { title: string; description?: string; children?: ReactNode }) {
  return (
    <div className="empty-state">
      <h2>{title}</h2>
      {description && <p>{description}</p>}
      {children}
    </div>
  )
}

/** 渲染异常时显示可恢复的错误页，而不是整页空白。 */
export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }

  static getDerivedStateFromError(error: Error) {
    return { error }
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('Render error', error, info.componentStack)
  }

  render() {
    if (this.state.error) {
      return (
        <div className="feedback feedback-error" role="alert">
          <p>页面出现错误：{this.state.error.message}</p>
          <button type="button" className="button" onClick={() => this.setState({ error: null })}>
            重新加载此页
          </button>
        </div>
      )
    }
    return this.props.children
  }
}
