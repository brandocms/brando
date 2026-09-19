import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('has cache and clears cache', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  // create a cached page
  await page.goto('/')
  await expect(page.getByRole('link', { name: 'Brando CMS' })).toBeVisible()

  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'Cache' }).click()
  await expect(page).toHaveURL('/admin/config/cache')

  await syncLV(page)
  // Query caches survive individual SQL sandboxes, so other pages may already
  // be cached. Clear the homepage's single-entry cache, not every pages row.
  const cachedPage = page.getByRole('row')
    .filter({ has: page.getByRole('cell', { name: 'pages', exact: true }) })
    .filter({ has: page.getByRole('cell', { name: '#1', exact: true }) })
  await expect(cachedPage).toBeVisible()

  await page.screenshot({ path: testInfo.outputPath('cache-desktop.png'), fullPage: true })
  await cachedPage.getByRole('button', { name: /^Clear cache/ }).click()
  await expect(cachedPage).toHaveCount(0)
  await expect(page.getByRole('cell', { name: 'users', exact: true }).first()).toBeVisible()
  await page.getByRole('button', { name: 'Empty all caches' }).click()
  await expect(
    page.getByRole('cell', { name: 'pages', exact: true })
  ).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'No cached entries' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('cache-empty-desktop.png'), fullPage: true })
})
