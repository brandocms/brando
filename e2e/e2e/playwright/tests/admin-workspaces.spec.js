import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

test.use({ viewport: { width: 1440, height: 1000 } })

const screens = [
  ['dashboard', '/admin', 'Dashboard'],
  ['pages', '/admin/pages', 'Pages & Sections'],
  ['modules', '/admin/config/content/modules', 'Content Modules'],
  ['navigation', '/admin/config/navigation/menus', 'Navigation'],
  ['menu-editor', '/admin/config/navigation/menus/update/1', 'Edit menu'],
  ['files', '/admin/assets/files', 'Files'],
  ['videos', '/admin/assets/videos', 'Videos'],
  ['seo', '/admin/config/seo', 'Update SEO'],
  ['identity', '/admin/config/identity', /Update identity/],
  ['globals', '/admin/globals', 'Globals'],
]
for (const [name, route, heading] of screens) {
  test(`${name} workspace at desktop and mobile sizes`, async ({ page }, testInfo) => {
    expect((await page.request.post('/e2e/admin-workspace-fixtures')).ok()).toBeTruthy()
    await page.goto(route)
    await syncLV(page)
    await expect(page.getByRole('heading', { level: 1, name: heading })).toBeVisible()
    await expect(page.locator('.admin-workspace')).toBeVisible()
    await expect(page.locator('.phx-error')).toHaveCount(0)
    await page.screenshot({ path: testInfo.outputPath(`${name}-desktop.png`), fullPage: true })
    if (name === 'modules') {
      await page.getByTestId('children-button').filter({ visible: true }).first().press('Enter')
      await expect(page.locator('.child-row').first()).toBeVisible()
      await page.evaluate(() => window.scrollTo(0, 0))
      await expect.poll(() => page.evaluate(() => scrollY)).toBe(0)
      await page.screenshot({ path: testInfo.outputPath('modules-expanded-desktop.png'), fullPage: true })
    }
    await page.setViewportSize({ width: 390, height: 844 })
    await page.evaluate(() => window.scrollTo(0, 0))
    await expect.poll(() => page.evaluate(() => scrollY)).toBe(0)
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
    await page.screenshot({ path: testInfo.outputPath(`${name}-mobile.png`), fullPage: true })
  })
}
