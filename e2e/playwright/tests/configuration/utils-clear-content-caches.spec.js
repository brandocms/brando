import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Utilities → Clear content caches, for content a script or data migration
// wrote outside the admin. The E2E admin is a superuser. Driven in
// Norwegian, so the locators name the translated labels.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('a superuser clears the content caches, sees what went, and Activity records it', async ({ page }) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)

  const row = page.locator('#utils-content-caches')
  await expect(row.getByRole('heading', { name: 'Innholdsbuffere', level: 3 })).toBeVisible()
  await expect(page.locator('#utils-content-caches-cleared')).toHaveCount(0)

  await row.getByRole('button', { name: 'Tøm innholdsbuffere', exact: true }).click()
  await syncLV(page)
  await expect(page.locator('#utils-content-caches-cleared')).toBeVisible()

  await page.goto('/admin/config/activity')
  await syncLV(page)
  await expect(page.locator('.activity-action', { hasText: 'Tømte hurtigbuffere' }).first()).toBeVisible()
})
