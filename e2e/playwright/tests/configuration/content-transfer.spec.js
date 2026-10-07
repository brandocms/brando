import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { readFile } from 'node:fs/promises'

// The export, review, import and recovery flows are LiveView tests in
// test/brando_admin/live/content_transfer_live_test.exs. What stays here
// needs a browser: keyboard focus, focus outlines, scrolling the diff, and the
// layout at a phone's width.

async function fitsPhone(page) {
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
}

test('export: keyboard selection, field pills and a phone-width layout', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1050 })
  expect((await page.request.post('/e2e/setup_fixtures/content-transfer')).ok()).toBeTruthy()
  await page.goto('/admin/config/import-export')
  await syncLV(page)

  // A whole entry is selected with Space and keeps focus.
  await page.getByLabel('Search saved content').fill('Campaign')
  await expect(page.locator('.transfer-entry')).toHaveCount(1)
  const select = page.getByRole('button', { name: 'Select Campaign launch', exact: true })
  await select.focus()
  await expect(select).toBeFocused()
  await select.press('Space')
  await expect(select).toHaveAttribute('aria-pressed', 'true')
  await expect(select).toBeFocused()

  // A field pill is reached with Tab, shows its outline, and toggles with
  // Space and Enter without losing focus.
  await page.goto('/admin/config/import-export')
  await syncLV(page)
  await page.getByText('Advanced export options', { exact: true }).click()
  await page.getByLabel('Export scope', { exact: true }).selectOption('fields')
  await expect(page.getByRole('button', { name: 'Prepare export', exact: true })).toBeDisabled()
  await page.getByLabel('Search saved content').fill('Campaign')
  await expect(page.locator('.transfer-entry')).toHaveCount(1)
  const row = page.locator('.transfer-entry').filter({ has: page.getByRole('heading', { name: 'Campaign launch', exact: true }) }).first()
  const field = row.getByRole('button', { name: 'Blocks', exact: true })
  await field.focus()
  await page.keyboard.press('Shift+Tab')
  await page.keyboard.press('Tab')
  await expect(field).toBeFocused()
  await expect(field).toHaveCSS('outline-style', 'solid')
  await field.press('Space')
  await expect(page.locator('.transfer-summary')).toContainText('1 field selected')
  await field.press('Space')
  await expect(page.getByRole('button', { name: 'Prepare export', exact: true })).toBeDisabled()
  await field.press('Enter')
  await expect(field).toHaveAttribute('aria-pressed', 'true')
  await expect(field).toBeFocused()
  await expect(field).toHaveCSS('outline-style', 'solid')

  await page.getByLabel('Search saved content').fill('')
  await expect.poll(() => page.locator('.transfer-entry').count()).toBeGreaterThan(1)
  await expect(field).toHaveAttribute('aria-pressed', 'true')
  await page.getByLabel('Search saved content').blur()
  await fitsPhone(page)
  await page.getByRole('link', { name: /Review selection/ }).click()
  await expect(page.getByRole('complementary', { name: 'Your export' })).toBeInViewport()
  await page.setViewportSize({ width: 1440, height: 1050 })
  await page.getByRole('button', { name: 'Prepare export', exact: true }).click()
  await expect(page.getByRole('heading', { name: 'Your bundle is ready' })).toBeVisible()
  await fitsPhone(page)
})

test('import: keyboard order, a scrollable diff and a phone-width layout', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1050 })
  expect((await page.request.post('/e2e/setup_fixtures/content-transfer-media')).ok()).toBeTruthy()
  await page.goto('/admin/config/import-export')
  await syncLV(page)
  await page.getByRole('button', { name: 'Select Campaign launch', exact: true }).click()
  await page.locator('#transfer-export-options input[name="media"]').uncheck()
  await page.getByRole('button', { name: 'Prepare export', exact: true }).click()
  const downloading = page.waitForEvent('download')
  await page.getByRole('link', { name: 'Download content bundle' }).click()
  const binary = await readFile(await (await downloading).path())

  await page.getByRole('button', { name: 'Import content', exact: true }).click()
  await page.locator('#transfer-upload-form input[type=file]').setInputFiles({ name: 'campaign-media.zip', mimeType: 'application/zip', buffer: binary })
  await expect(page.getByRole('button', { name: 'Review bundle', exact: true })).toBeEnabled()
  await fitsPhone(page)
  await page.setViewportSize({ width: 1440, height: 1050 })
  await page.getByRole('button', { name: 'Review bundle', exact: true }).click()
  await expect(page.locator('#transfer-entry-mappings')).toBeVisible()

  // Publication follows the import action in the tab order, with its outline.
  const publication = page.getByLabel('Publication', { exact: true })
  await page.locator('select[id^="entry-action-"]').focus()
  await page.keyboard.press('Tab')
  await expect(publication).toBeFocused()
  await expect(publication).toHaveCSS('outline-style', 'solid')
  await fitsPhone(page)
  await page.setViewportSize({ width: 1440, height: 1050 })

  // A long diff scrolls inside its own region from the keyboard.
  await page.getByLabel('Import action', { exact: true }).selectOption('update')
  await page.getByLabel('Destination entry', { exact: true }).selectOption({ label: 'Destination page · English' })
  await page.getByLabel('URI', { exact: true }).fill('destination-media-copy')
  for (const name of ['courtyard.jpg', 'collection-detail.jpg']) {
    await page.getByLabel(`Destination for images/${name}`, { exact: true }).selectOption({ label: `images/${name}` })
  }
  await page.getByText('Review fields & content', { exact: true }).click()
  const diff = page.locator('.admin-text-diff')
  await expect(diff.locator('ins')).toContainText(['Image · Hero: courtyard.jpg'])
  await fitsPhone(page)
  const viewport = diff.getByRole('region')
  await viewport.focus()
  await expect(viewport).toBeFocused()
  await viewport.press('End')
  await expect(diff.locator('ins').last()).toBeInViewport()
  await viewport.press('Home')
})
