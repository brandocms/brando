import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

test.use({ viewport: { width: 1440, height: 1000 } })

const screens = [
  ['dashboard', '/admin', 'Dashboard'],
  ['modules', '/admin/config/content/modules', 'Block modules'],
  ['navigation', '/admin/config/navigation/menus', 'Navigation'],
  ['files', '/admin/assets/files', 'Files'],
  ['videos', '/admin/assets/videos', 'Videos'],
  ['seo', '/admin/config/seo', 'SEO'],
  ['identity', '/admin/config/identity', 'Identity'],
  ['globals', '/admin/globals', 'Globals'],
]
// The pages listing and the menu editor have these checks in
// admin-layout-audit.spec.js, which opens them for their layout already.

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
      await expect(firstRow.locator('.entry-link').first()).toHaveCSS('font-size', '14px')
      // Rows sit in the listing's one frame, not as separate rounded pills:
      // the first only rounds its top corners to the frame's
      await expect(page.locator('.content-list-frame')).toHaveCSS('border-radius', '6px')
      await expect(firstRow).toHaveCSS('border-radius', '5px 5px 0px 0px')
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
    // 918125724 marks the shared layout container with admin-workspace so the
    // listing CSS need not reach for :has(); the LiveView keeps its own
    // .admin-workspace inside it, so the class legitimately nests.
    await expect(page.locator('.admin-workspace:not(.drawer)').first()).toBeVisible()
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
