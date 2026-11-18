import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Utilities → Clear caches, the admin's one cache action, for content a
// script or data migration wrote outside the admin. The E2E admin is a
// superuser. Driven in Norwegian, so the locators name the translated labels.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('a superuser clears the caches, sees what went, and Activity records it', async ({ page }) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)

  const row = page.locator('#utils-caches')
  await expect(row.getByRole('heading', { name: 'Buffere', level: 3 })).toBeVisible()
  await expect(page.locator('#utils-caches-cleared')).toHaveCount(0)

  await row.getByRole('button', { name: 'Tøm buffere', exact: true }).click()
  await syncLV(page)
  await expect(page.locator('#utils-caches-cleared')).toBeVisible()

  await page.goto('/admin/config/activity')
  await syncLV(page)
  await expect(page.locator('.activity-action', { hasText: /^Tømt$/ }).first()).toBeVisible()
  await expect(page.locator('.activity-entry', { hasText: 'Buffere' }).first()).toBeVisible()
})

test('the old Cache screen is gone from the menu, and its address opens Utilities', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  const nav = page.locator('#nav')
  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()
  const operations = nav.getByRole('group', { name: 'Drift' })
  await expect(operations.getByRole('link', { name: 'Verktøy' })).toBeVisible()
  await expect(nav.locator('a[href="/admin/config/cache"]')).toHaveCount(0)

  await page.goto('/admin/config/cache')
  await expect(page).toHaveURL('/admin/config/utils')
  await syncLV(page)
  await expect(page.locator('#utils-caches')).toBeVisible()
})
