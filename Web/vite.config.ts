import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

// 开发时由 Vite 提供页面，/api 请求转发给本机的 closet-server。
// 服务端只接受来自自身的 Origin，转发时把浏览器的 Origin 改写为服务端地址。
const serverOrigin = process.env.CLOSET_SERVER ?? 'http://127.0.0.1:8765'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      '/api': {
        target: serverOrigin,
        configure: (proxy) => {
          proxy.on('proxyReq', (proxyReq) => {
            proxyReq.setHeader('host', new URL(serverOrigin).host)
            if (proxyReq.getHeader('origin')) proxyReq.setHeader('origin', serverOrigin)
          })
        },
      },
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  },
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    include: ['src/**/*.test.{ts,tsx}'],
  },
})
