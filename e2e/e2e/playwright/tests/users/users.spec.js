import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('creates, updates and deletes a user with content transfer', async ({ page }) => {
  const email = 'coverage-editor@brandocms.com'
  const groups = process.env.BRANDO_AUTHORIZATION_MODE === 'groups'

  await page.goto('/admin/users')
  await syncLV(page)
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
  if (!groups) await expect(userRow).toContainText('editor')

  await userRow.getByRole('link', { name: 'Coverage Editor →' }).click()
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
})
