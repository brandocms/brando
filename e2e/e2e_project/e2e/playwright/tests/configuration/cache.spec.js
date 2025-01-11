import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('has cache and clears cache', async ({ page }) => {
  // create a cached page
  await page.goto('/')
  await expect(page.getByRole('link', { name: 'Brando CMS' })).toBeVisible()

  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'Cache' }).click()
  await expect(page).toHaveURL('/admin/config/cache')
  await syncLV(page)

  await expect(
    page.getByRole('cell', { name: 'pages', exact: true })
  ).toBeVisible()
  await expect(page.locator('td').getByText('#1')).toBeVisible()

  await page.getByRole('button', { name: 'Empty all caches' }).click()
  await expect(page.locator('td').getByText('pages')).not.toBeVisible()
})
