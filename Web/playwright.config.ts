import { defineConfig } from '@playwright/test'

// 端到端测试访问真实运行的 closet-server。服务端由 scripts/e2e-server.sh 启动，
// 它会先导入样例备份，再托管 Web/dist（运行前需要 npm run build）。
// 整次运行共用一个数据目录：只读检查先跑，会修改数据的流程依赖它们之后再跑。
const port = Number(process.env.CLOSET_E2E_PORT ?? 18766)
const baseURL = `http://127.0.0.1:${port}`

export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL,
    browserName: 'chromium',
    locale: 'zh-CN',
    trace: 'retain-on-failure',
  },
  projects: [
    { name: 'read-only', testMatch: /wardrobe\.spec\.ts$/ },
    { name: 'workflows', testMatch: /workflows\.spec\.ts$/, dependencies: ['read-only'] },
  ],
  webServer: {
    command: '../scripts/e2e-server.sh',
    url: `${baseURL}/api/v1/health`,
    reuseExistingServer: false,
    timeout: 300_000,
    stdout: 'pipe',
    stderr: 'pipe',
  },
})
