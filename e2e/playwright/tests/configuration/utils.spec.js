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
  await maintenance.getByRole('button', { name: 'Recalculate colors', exact: true }).click()
  await expect(page.getByText('Read the dominant color of every image again? This runs in the background.')).toBeVisible()
  await page.getByRole('button', { name: 'OK', exact: true }).click()
  await syncLV(page)
  await expect(page.getByText('Recalculating dominant colors in the background.')).toBeAttached()
})
