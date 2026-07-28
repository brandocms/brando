// Benchmark runner config. Separate from playwright.config.js so the bench
// never runs as part of the regression suite (testDir there is ./tests).
//
//   pnpm playwright test --config bench/playwright.bench.config.js
//
// Requires the large fixtures:
//   cd e2e && source .envrc && MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs

import { defineConfig } from '@playwright/test'

export default defineConfig({
  webServer: {
    // Resolved against this config file's directory (bench/), so it takes three
    // levels to reach the e2e project root that holds mix.exs. Latent until now
    // because `reuseExistingServer` skips the spawn whenever a server is up.
    cwd: '../../../',
    command: 'env MIX_ENV=e2e PORT=4444 mix phx.server',
    url: 'http://localhost:4444/admin/login',
    stdout: 'pipe',
    stderr: 'pipe',
    wait: { stdout: /Running.*Endpoint.*at/ },
    reuseExistingServer: true,
    gracefulShutdown: { signal: 'SIGTERM', timeout: 5000 },
  },
  testDir: '.',
  fullyParallel: false,
  workers: 1,
  // A benchmark that silently retries is a benchmark that lies about latency.
  retries: 0,
  timeout: 600000,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4444/',
    ignoreHTTPSErrors: true,
    // Never inherit an unlimited action timeout — a bad locator would otherwise
    // burn the full 10-minute test timeout instead of failing immediately.
    actionTimeout: 20000,
    navigationTimeout: 120000,
  },
})
