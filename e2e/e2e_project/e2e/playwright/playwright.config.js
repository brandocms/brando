// @ts-check
const { defineConfig, devices } = require('@playwright/test')

/**
 * Read environment variables from file.
 * https://github.com/motdotla/dotenv
 */
// require('dotenv').config({ path: path.resolve(__dirname, '.env') });

/**
 * @see https://playwright.dev/docs/test-configuration
 */
module.exports = defineConfig({
  /* Run your local dev server before starting the tests */
  webServer: {
    // Move up test project
    cwd: '../../',
    command: 'env MIX_ENV=e2e PORT=4444 mix phx.server',
    // Used by playwright to check if the server is running
    url: 'http://localhost:4444/',
    stdout: 'pipe',
    stderr: 'pipe',
    reuseExistingServer: !process.env.CI
  },
  testDir: './tests',
  /* Run tests in files in parallel */
  fullyParallel: true,
  /* Fail the build on CI if you accidentally left test.only in the source code. */
  forbidOnly: !!process.env.CI,
  /* Opt out of parallel tests on CI. */
  workers: process.env.CI ? 1 : undefined,
  retries: process.env.CI ? 2 : 0,
  reporter: process.env.CI ? [['github'], ['html'], ['dot']] : [['list']],
  use: {
    /* Base URL to use in actions like `await page.goto('/')`. */
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    baseURL: 'http://localhost:4444/',
    ignoreHTTPSErrors: true
  },
  // globalTeardown: require.resolve('./teardown'),

  /* Configure projects for major browsers */
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] }
    }

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
    // {
    //   name: 'Google Chrome',
    //   use: { ...devices['Desktop Chrome'], channel: 'chrome' },
    // },
  ]
})
