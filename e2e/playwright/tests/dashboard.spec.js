// playwright/tests/my-test.spec.ts
import { test, expect } from '../test-support/setupAuth'

test('should go straight to dashboard if authenticated', async ({ page }) => {
  // Go to the /admin page
  await page.goto('/admin')

  // Wait for navigation and check that the URL is /admin/login
  await expect(page).toHaveURL('/admin')
})

test('updates dashboard content when permissions change without reloading', async ({ page, secondUserPage }) => {
  test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups', 'Requires explicit group mode')
  expect((await page.request.post('/e2e/admin-workspace-fixtures')).ok()).toBeTruthy()
  expect((await page.request.post('/e2e/dashboard-access/author')).ok()).toBeTruthy()
  await secondUserPage.goto('/admin')
  const dashboard = secondUserPage.locator('.dashboard-workspace')
  const drafts = dashboard.locator('.workspace-panel').filter({ has: secondUserPage.getByRole('heading', { name: 'Drafts', exact: true }) })
  await expect(drafts.getByRole('link', { name: 'Studio notes', exact: true })).toBeVisible()
  expect((await page.request.post('/e2e/dashboard-access/reader')).ok()).toBeTruthy()
  await expect(drafts.getByText('No drafts', { exact: true })).toBeVisible()
  await expect(dashboard.getByRole('link', { name: 'Studio notes', exact: true })).toHaveCount(0)
  await expect(dashboard.getByText('Studio notes', { exact: true })).toBeVisible()
  expect((await page.request.post('/e2e/dashboard-access/backend')).ok()).toBeTruthy()
  await expect(dashboard.getByText('Studio notes', { exact: true })).toHaveCount(0)
  await expect(dashboard.getByText('No recent content', { exact: true })).toBeVisible()
  await expect(dashboard.locator('.dashboard-shortcut')).toHaveCount(0)
  await expect(secondUserPage).toHaveURL('/admin')
})
