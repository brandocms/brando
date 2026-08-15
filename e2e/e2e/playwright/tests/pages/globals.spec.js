import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('updates and persists content globals', async ({ page }) => {
  await page.goto('/admin/config/global_sets/create')
  await syncLV(page)

  await page.getByLabel('Label', { exact: true }).fill('Coverage globals')
  await page.getByLabel('Key', { exact: true }).fill('coverage')
  await page.getByRole('button', { name: 'Add entry' }).click()

  const globalVar = page.locator('#global_set_vars_0-edit')
  await globalVar.locator('.variable-header').click()
  await page.locator('#global_set_vars_0_key').fill('announcement')
  await page.locator('#global_set_vars_0_label').fill('Announcement')
  await page
    .locator('#global_set_vars_0_width-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: /^Half/ }).click()
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL('/admin/config/global_sets')

  await page.goto('/admin/globals')
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Globals' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Coverage globals' })).toBeVisible()

  await page.getByLabel('Announcement').fill('Site maintenance at midnight')
  await page.getByRole('button', { name: 'Save' }).click()
  await syncLV(page)
  await expect(page.getByText('Global set updated')).toBeAttached()

  await page.reload()
  await syncLV(page)
  await expect(page.getByLabel('Announcement')).toHaveValue('Site maintenance at midnight')
})
