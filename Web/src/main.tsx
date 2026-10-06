import { StrictMode } from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { applyAppearance, loadAppearance } from './app/appearance'
import './styles.css'

// 在首次渲染前应用外观偏好，避免页面先以默认外观闪现。
applyAppearance(loadAppearance())

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
)
