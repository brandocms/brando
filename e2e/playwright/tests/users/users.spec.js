import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('creates, updates and deletes a user with content transfer', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const email = 'coverage-editor@brandocms.com'
  const groups = process.env.BRANDO_AUTHORIZATION_MODE === 'groups'

  const fixtureResponse = await page.request.post('/e2e/user-directory/create')
  expect(fixtureResponse.ok()).toBe(true)
  const fixture = await fixtureResponse.json()
  try {
    await page.goto('/admin/users')
    await syncLV(page)
    const adminRow = page.locator('.list-row').filter({ hasText: 'admin@brandocms.com' })
    await expect(adminRow.locator('.user-avatar img')).toBeVisible()
    await expect.poll(() => adminRow.locator('.user-avatar img').evaluate(img => img.naturalWidth)).toBeGreaterThan(0)
    await expect(adminRow.locator('.user-role')).toContainText('superuser')
    await expect(adminRow.locator('.user-last-seen time')).toHaveAttribute('datetime', '2026-09-07T12:34:00Z')
    await expect(adminRow.locator('.user-last-login time')).toHaveAttribute('datetime', '2026-09-06T08:15:00Z')
    await expect(page.locator('.user-directory-columns')).toContainText(groups ? 'Legacy role' : 'Role')
    await page.screenshot({ path: testInfo.outputPath('users-desktop.png'), fullPage: true })
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)

    await page.getByLabel('Name', { exact: true }).fill('Coverage Editor')
    await page.getByLabel('Email', { exact: true }).fill(email)
    await page.getByLabel('Password', { exact: true }).fill('brandocms')
    await page.getByLabel('English').check()
    if (groups) await expect(page.getByLabel('Editor', { exact: true })).toHaveCount(0)
    else await page.getByLabel('Editor').check()
    await page.getByTestId('submit').click()

    await expect(page).toHaveURL('/admin/users')
    await syncLV(page)
    let userRow = page.locator('.content-list .list-row').filter({ hasText: email })
    await expect(userRow).toContainText('Coverage Editor')
    await expect(userRow.locator('.user-role')).toContainText(groups ? 'user' : 'editor')
    await expect(userRow.locator('.user-last-login')).toContainText('Not recorded')

    const search = page.getByRole('textbox', { name: 'Filter by Name', exact: true })
    await search.fill('Coverage Editor')
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(userRow).toContainText(email)
    await search.fill('')
    await userRow.getByRole('link', { name: 'Coverage Editor', exact: true }).click()
    await syncLV(page)
    await page.getByLabel('Name', { exact: true }).fill('Updated Coverage Editor')
    await page.getByTestId('submit').click()

    await expect(page).toHaveURL('/admin/users')
    await syncLV(page)
    userRow = page.locator('.content-list .list-row').filter({ hasText: email })
    await expect(userRow).toContainText('Updated Coverage Editor')

    await userRow.getByTestId('circle-dropdown-button').click()
    await userRow.getByRole('button', { name: 'Delete user' }).click()

    const transferModal = page.locator('#transfer-content-modal')
    await expect(transferModal).toBeVisible()
    await expect(transferModal).toContainText('This user has no content to transfer.')
    await transferModal.getByRole('button', { name: 'Select user...' }).click()
    await transferModal.getByRole('button', { name: /Brando Admin/ }).click()
    await transferModal.getByRole('button', { name: 'Transfer & Delete' }).click()
    await syncLV(page)

    await expect(page.locator('.content-list .list-row').filter({ hasText: email })).toHaveCount(0)
  } finally {
    await page.request.post('/e2e/user-directory/cleanup', { data: fixture })
  }
})
