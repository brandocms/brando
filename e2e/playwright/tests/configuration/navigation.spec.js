import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Deactivating, creating and removing menu items are LiveView tests in
// test/brando_admin/live/navigation_live_test.exs. Reordering needs a drag.

test('reorder menu items', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.locator('#nav-sections').getByRole('link', { name: 'Navigation' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await page.getByRole('link', { name: 'Main menu' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')

  await page.locator('.subform-handle').first().hover()
  await page.mouse.down()
  await page
    .locator('div:nth-child(9) > .subform-tools > .subform-handle')
    .hover()
  await page
    .locator('div:nth-child(9) > .subform-tools > .subform-handle')
    .hover()
  await page.waitForTimeout(300)
  await page.mouse.up()

  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await syncLV(page)

  await page.goto('/')

  // Wait for the menu items to be loaded
  await page.waitForSelector('[data-menu-item-key]')

  // Get all elements with data-menu-item-key in DOM order
  const menuItemKeys = await page.$$eval('[data-menu-item-key]', (elements) =>
    elements.map((el) => el.getAttribute('data-menu-item-key'))
  )

  // Check that both keys are present
  expect(menuItemKeys).toContain('brando')
  expect(menuItemKeys).toContain('guides')

  // Find the indices of 'brando' and 'guides'
  const brandoIndex = menuItemKeys.indexOf('brando')
  const guidesIndex = menuItemKeys.indexOf('guides')

  // Assert that 'brando' comes after 'guides'
  expect(brandoIndex).toBeGreaterThan(guidesIndex)
})
