// @ts-check
const { defineConfig, devices } = require('@playwright/test')

const port = process.env.BRANDO_E2E_PORT || process.env.PORT || '4444'

if (!/^\d+$/.test(port) || Number(port) < 1024 || Number(port) > 65535) {
  throw new Error(`Invalid BRANDO_E2E_PORT: ${port}`)
}

const host = process.env.BRANDO_URL_HOST || 'localhost'
const baseURL = (
  process.env.BRANDO_E2E_BASE_URL || `http://${host}:${port}`
).replace(/\/$/, '')

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  /* Run your local dev server before starting the tests */
  webServer: {
    cwd: '../../',
    command: 'mix phx.server',
    env: {
      ...process.env,
      MIX_ENV: 'e2e',
      PORT: port,
      BRANDO_E2E_PORT: port,
      BRANDO_URL_PORT: port,
    },
    url: `${baseURL}/admin/login`,
    stdout: 'pipe',
    stderr: 'pipe',
    wait: { stdout: /Running.*Endpoint.*at/ },
    reuseExistingServer:
      process.env.BRANDO_E2E_REUSE_SERVER === undefined
        ? !process.env.CI
        : process.env.BRANDO_E2E_REUSE_SERVER === 'true',
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5000 },
  },
  testDir: './tests',
  fullyParallel: false,
  forbidOnly: !!process.env.CI,
  timeout: 60000,
  // SQL sandboxes isolate rows, but application-wide PubSub and caches can still
  // leak transient state between workers. Keep every E2E run deterministic.
  workers: 1,
  retries: process.env.CI ? 2 : 1,
  reporter: process.env.CI ? [['github'], ['html'], ['dot']] : [['list']],
  use: {
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    baseURL: `${baseURL}/`,
    ignoreHTTPSErrors: true,
  },
  globalTeardown: require.resolve('./teardown'),

  projects: [
    // {
    //   name: 'chromium',
    //   use: { ...devices['Desktop Chrome'] },
    // },

    // {
    //   name: 'firefox',
    //   use: { ...devices['Desktop Firefox'] }
    // },

    // {
    //   name: 'webkit',
    //   use: { ...devices['Desktop Safari'] }
    // }

    /* Test against mobile viewports. */
    // {
    //   name: 'Mobile Chrome',
    //   use: { ...devices['Pixel 5'] },
    // },
    // {
    //   name: 'Mobile Safari',
    //   use: { ...devices['iPhone 12'] },
    // },

    /* Test against branded browsers. */
    // {
    //   name: 'Microsoft Edge',
    //   use: { ...devices['Desktop Edge'], channel: 'msedge' },
    // },
    {
      name: 'Google Chrome',
      use: { ...devices['Desktop Chrome'], channel: 'chromium' },
    },
  ],
})
