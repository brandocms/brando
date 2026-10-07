// Playwright config for scripts/admin-ui-references.mjs. It reuses the E2E
// config against an already running server and only changes what the reference
// screenshots need: their own output folder, the reference flows next to the
// specs, and Chromium without font hinting so Linux text matches macOS more
// closely (the flag is harmless on macOS).
const path = require('node:path')
const base = require('../playwright.config.js')

const root = path.resolve(__dirname, '..')
const fontArgs = ['--font-render-hinting=none']

module.exports = {
  ...base,
  testDir: root,
  testMatch: ['tests/**/*.spec.js', 'scripts/admin-ui-references.spec.js'],
  outputDir: path.join(root, 'test-results/admin-ui-references'),
  globalTeardown: undefined,
  reporter: [['list']],
  retries: 1,
  webServer: { ...base.webServer, cwd: path.resolve(root, '..'), reuseExistingServer: true },
  use: { ...base.use, launchOptions: { args: fontArgs } },
  projects: base.projects.map(project => ({
    ...project,
    use: { ...project.use, launchOptions: { ...(project.use.launchOptions || {}), args: fontArgs } },
  })),
}
