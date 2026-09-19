import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('activates an uploaded frontend build and returns to release assets', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/config/assets')
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Frontend assets', exact: true })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('frontend-assets-empty-desktop.png'), fullPage: true })

  const response = await page.request.post('/e2e/frontend-assets/create')
  expect(response.ok()).toBe(true)
  const { builds } = await response.json()
  try {
    await page.getByRole('button', { name: 'Refresh', exact: true }).click()
    const row = page.locator(`#asset-set-${builds[0].id}`)
    await expect(row).toContainText(builds[0].name)
    page.on('dialog', dialog => dialog.accept())
    await row.getByRole('button', { name: 'Activate build', exact: true }).click()
    await expect(page.locator('.frontend-assets-current.uploaded')).toContainText(builds[0].name)
    await expect(row.locator('.frontend-assets-build__status')).toHaveText('Active')
    await expect(row.locator('.frontend-assets-build__actions')).toBeEmpty()
    await expect(page.locator('.frontend-assets-table thead')).toContainText('Status')
    await expect(page.locator('.frontend-assets-current__meta > div').last()).toContainText('2 files · 33 B')
    await page.screenshot({ path: testInfo.outputPath('frontend-assets-desktop.png'), fullPage: true })
    await page.getByRole('button', { name: 'Use release assets', exact: true }).click()
    await expect(page.locator('.frontend-assets-current')).toContainText('Release assets')
    await expect(row).toContainText('Available')
    await page.setViewportSize({ width: 390, height: 844 })
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
  } finally {
    await page.request.post('/e2e/frontend-assets/cleanup', { data: { names: builds.map(build => build.name) } })
  }
})
