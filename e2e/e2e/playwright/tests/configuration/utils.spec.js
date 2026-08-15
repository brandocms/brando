import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('runs administrative utilities and displays system information', async ({ page }) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)

  await expect(page.getByRole('heading', { name: 'Utils' })).toBeVisible()
  await expect(page.getByText('These utilities are for administrative purposes')).toBeVisible()

  const utilities = page.locator('.utils-live')
  await expect(utilities.getByText('Version', { exact: true })).toBeVisible()
  await expect(utilities.getByText('Timezone', { exact: true })).toBeVisible()
  await expect(utilities.getByText('Locale', { exact: true })).toBeVisible()
  await expect(utilities.getByText('Concurrency', { exact: true })).toBeVisible()

  const syncIdentifiersRow = utilities.locator('tr').filter({ hasText: 'Sync all identifiers' })
  await syncIdentifiersRow.getByRole('button', { name: 'Execute' }).click()
  await syncLV(page)
  await expect(page.getByText('Identifiers synced.')).toBeAttached()

  const sitemapRow = utilities.locator('tr').filter({ hasText: 'Generate sitemap' })
  await sitemapRow.getByRole('button', { name: 'Execute' }).click()
  await syncLV(page)
  await expect(page.getByText('Generated sitemap.')).toBeAttached()
})
