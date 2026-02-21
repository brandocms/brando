import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('lists galleries and edits a gallery', async ({ page }) => {
  await page.goto('/admin')

  // Navigate to galleries via menu (expand Assets submenu first)
  await page.getByText('Assets').click()
  await page.getByRole('link', { name: 'Galleries' }).click()
  await syncLV(page)

  // Verify we're on the galleries listing page
  await expect(page).toHaveURL(/\/admin\/assets\/galleries/)

  // Verify gallery rows are visible (seeded 2 galleries)
  const rows = page.locator('.content-list .list-row')
  await expect(rows).toHaveCount(2)

  // Verify config_target is shown
  await expect(rows.first()).toContainText('Gallery')

  // Click edit on the first gallery via the dropdown menu
  await rows.first().locator('.circle-dropdown').click()
  await page.getByRole('button', { name: /Edit/ }).click()
  await syncLV(page)

  // Verify we're on the edit page
  await expect(page).toHaveURL(/\/admin\/assets\/galleries\/update\//)

  // Edit the config_target field
  const configTargetInput = page.getByRole('textbox', { name: 'Configuration target' })
  await expect(configTargetInput).toBeVisible()
  await configTargetInput.click()
  await configTargetInput.fill('updated_target')

  // Save the form
  await page.getByTestId('submit').click()

  // Verify we're back on the listing page
  await expect(page).toHaveURL(/\/admin\/assets\/galleries/)
  await syncLV(page)

  // Verify the updated config_target is shown
  await expect(rows.first()).toContainText('updated_target')
})
