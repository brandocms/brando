import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('runs administrative utilities and displays system information', async ({ page }) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)

  await expect(page.getByRole('heading', { name: 'Utilities', level: 1 })).toBeVisible()
  await expect(page.getByText('Administrative tools for this workspace.')).toBeVisible()

  const utilities = page.locator('.utils-workspace')
  await expect(utilities.locator('.utils-version')).toHaveText(/^Brando \S+/)
  const systemInfo = utilities.locator('.utils-system-info')
  await expect(systemInfo.getByText('Timezone', { exact: true })).toBeVisible()
  await expect(systemInfo.getByText('Locale', { exact: true })).toBeVisible()
  await expect(systemInfo.getByText('Concurrency', { exact: true })).toBeVisible()
  await expect(systemInfo.getByText('Image jobs', { exact: true })).toBeVisible()
  await expect(systemInfo.locator('dd')).toHaveText([/\S+/, /\S+/, /^\d+$/, /^\d+$/])

  const maintenance = utilities.getByRole('region', { name: 'Maintenance' })
  await maintenance.getByRole('button', { name: 'Sync identifiers', exact: true }).click()
  await syncLV(page)
  await expect(page.getByText('Identifiers synced.')).toBeAttached()

  // The E2E app has no sitemap module; exercise the command and its feedback.
  await maintenance.getByRole('button', { name: 'Generate sitemap', exact: true }).click()
  await syncLV(page)
  await expect(page.getByText('Generated sitemap.')).toBeAttached()

  // Both bulk image tools ask first. Recalculating colors is the cheaper of
  // the two to run in full, since E2E executes Oban jobs inline.
  await expect(maintenance.getByRole('heading', { name: 'Image sizes', level: 3 })).toBeVisible()
  await expect(maintenance.getByRole('heading', { name: 'Dominant colors', level: 3 })).toBeVisible()
  await expect(maintenance.getByRole('button', { name: 'Recreate image sizes', exact: true })).toBeEnabled()
  // The seeded site has no images made with older settings.
  await expect(maintenance.getByText('All images match their settings', { exact: true })).toBeVisible()
  await expect(maintenance.getByRole('button', { name: 'Recreate changed images', exact: true })).toBeDisabled()
  await maintenance.getByRole('button', { name: 'Recalculate colors', exact: true }).click()
  const confirm = page.getByRole('dialog', { name: 'Read the dominant color of every image again?' })
  await expect(confirm).toContainText('This runs in the background.')
  await confirm.getByRole('button', { name: 'Recalculate colors', exact: true }).click()
  await syncLV(page)
  await expect(page.getByText('Recalculating dominant colors in the background.')).toBeAttached()
})

// E2E runs Oban inline, so the run ends within the click: what is left to
// see is how it ended. The fixture adds an image that recreates and one that
// cannot (no image type).
test('Image sizes counts a run and names the image it could not recreate', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/image-sizes-broken-image')).ok()).toBe(true)
  await page.goto('/admin/config/utils')
  await syncLV(page)

  const row = page.locator('#utils-image-sizes')
  const recreateAll = row.locator('button[phx-click=recreate_image_sizes]')
  await recreateAll.click()
  await page.locator('dialog[open] .admin-dialog-button.is-primary').click()
  await syncLV(page)

  await expect(row.locator('#work-status-image-sizes')).toHaveAttribute('data-status', 'failed')
  const failures = row.locator('#utils-image-failures')
  await expect(failures).toHaveAttribute('data-count', '1')
  const link = failures.locator('a[data-image-id]')
  await expect(link).toHaveCount(1)
  await expect(link).toHaveText('broken.unknown')
  await expect(link).toHaveAttribute('href', /^\/admin\/assets\/images\/update\/\d+$/)

  // The run is over: both of its images are done
  await expect(recreateAll).toBeEnabled()
  await expect(row.locator('#utils-image-sizes-running')).toHaveCount(0)

  // The name leads to the image in the media library
  const href = await link.getAttribute('href')
  await link.click()
  await expect(page).toHaveURL(href)
  await syncLV(page)
  await expect(page.locator('#utils-image-sizes')).toHaveCount(0)
  await expect(page.locator('form')).not.toHaveCount(0)
})
