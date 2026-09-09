const { defineConfig } = require('@playwright/test')
const port = process.env.BRANDO_TIPTAP_TEST_PORT || 4488
module.exports = defineConfig({
  testDir: '../../../test/javascript/tiptap', testMatch: '*.spec.js',
  outputDir: 'test-results/tiptap-components',
  timeout: 15000, fullyParallel: true, workers: 2,
  use: { baseURL: `http://127.0.0.1:${port}`, headless: true },
  webServer: {
    command: "bash -c 'cd ../.. && source .envrc && cd assets/backend && pnpm exec vite --config tiptap.vite.config.js'",
    url: `http://127.0.0.1:${port}/tiptap.html`, reuseExistingServer: false, timeout: 30000,
  },
})
