import { defineConfig } from '@playwright/test'

export default defineConfig({
  testDir: '.',
  testMatch: '*.spec.js',
  workers: 1,
  retries: 0,
  timeout: 90_000,
  expect: { timeout: 20_000 },
  outputDir: process.env.BRANDO_SMOKE_ARTIFACTS || '/tmp/brando-igniter-playwright',
  use: {
    baseURL: process.env.BRANDO_SMOKE_BASE_URL,
    headless: true,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
})
