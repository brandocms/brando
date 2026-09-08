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

// Keep these application LiveViews on the previously generated markup. They
// must inherit the shared design without opting in or regenerating templates.
for (const [name, route, heading] of [
  ['projects', '/admin/projects/projects', 'Projects'],
  ['clients', '/admin/projects/clients', 'Clients'],
  ['categories', '/admin/projects/categories', 'Categories'],
]) {
  test(`${name} blueprint listing inherits the workspace at desktop and mobile sizes`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await page.goto(route)
    await syncLV(page)
    const title = page.getByRole('heading', { level: 1, name: heading })
    await expect(title).toHaveCSS('font-size', '32px')
    await expect(page.getByRole('link', { name: 'Create new' })).toHaveCSS('background-color', 'rgb(37, 78, 63)')
    const firstRow = page.locator('.list-row').first()
    if (await firstRow.count()) {
      await expect(firstRow.locator('.entry-link').first()).toHaveCSS('font-size', '15px')
      await expect(firstRow).toHaveCSS('border-radius', '0px')
    }
    await page.screenshot({ path: testInfo.outputPath(`${name}-desktop.png`), fullPage: true })
    await page.setViewportSize({ width: 390, height: 844 })
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
    await expect(title).toBeVisible()
    if (await firstRow.locator('.listing-creator').count()) {
      await expect(firstRow.locator('.listing-creator')).toBeVisible()
    }
    await page.screenshot({ path: testInfo.outputPath(`${name}-mobile.png`), fullPage: true })
  })
}

for (const [name, route, heading] of screens) {
  test(`${name} workspace at desktop and mobile sizes`, async ({ page }, testInfo) => {
    expect((await page.request.post('/e2e/admin-workspace-fixtures')).ok()).toBeTruthy()
    await page.goto(route)
    await syncLV(page)
    await expect(page.getByRole('heading', { level: 1, name: heading })).toBeVisible()
    await expect(page.locator('.admin-workspace:not(.drawer)')).toBeVisible()
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
