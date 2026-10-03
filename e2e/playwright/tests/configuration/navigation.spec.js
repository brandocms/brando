import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('deactivate menu item', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.locator('#nav-sections').getByRole('link', { name: 'Navigation' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await page.getByRole('link', { name: 'Main menu' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')
  await page
    .locator('#menu_items_2_status-field-base')
    .getByTestId('status-published')
    .locator('circle')
    .click()
  await syncLV(page)
  await page
    .locator('#status-dropdown-menu_items_2_status')
    .getByText('Deactivated')
    .click()
  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')

  // now check if the menu item is deactivated on the frontend
  await page.goto('/')
  await expect(
    page.locator('[data-menu-item-key="documentation"]').getByText('Guides')
  ).not.toBeVisible()
})

test('create menu item', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.locator('#nav-sections').getByRole('link', { name: 'Navigation' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await page.getByRole('link', { name: 'Main menu' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')

  await page.getByRole('button', { name: 'Add entry' }).click()
  await page.locator('#menu_items_3_link_0_identifier_id-field-base .link-preview').click()
  await page.locator('#var-menu_items_3_link_0-link-config').getByRole('radio', { name: 'URL', exact: true }).check()
  await page.getByRole('textbox', { name: 'URL' }).click()
  await page.getByRole('textbox', { name: 'URL' }).fill('https://google.com')
  await page.getByRole('textbox', { name: 'URL' }).press('Tab')
  await page.getByRole('textbox', { name: 'Link text' }).fill('Google')
  await page
    .locator('#menu_items_3_link_0_link_target_blank-field-base')
    .click()
  await page
    .locator('#var-menu_items_3_link_0-link-config')
    .getByRole('button', { name: 'Done', exact: true })
    .click()
  await expect(
    page.locator('#menu_items_3_link_0_identifier_id-field-base')
  ).toContainText('Google')
  await expect(
    page.locator('#menu_items_3_link_0_identifier_id-field-base')
  ).toContainText('https://google.com')
  // Until set, the key follows the link text — not the "text" the new item's
  // placeholder link gave it on the first render, which the form posts back.
  const key = page.locator('#menu_items_3_key-disclosure')
  await expect(key.locator('.disclosed-text-summary code')).toHaveText('google')
  // The key sits behind its "Key: …" summary; opening it focuses the field
  await key.locator('.disclosed-text-summary').click()
  await page.locator('#menu_items_3_key').fill('new_item')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await syncLV(page)

  await page.goto('/')
  await expect(
    page.locator('[data-menu-item-key="new_item"]').getByText('Google')
  ).toBeVisible()
})

test('delete menu item', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.locator('#nav-sections').getByRole('link', { name: 'Navigation' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await page.getByRole('link', { name: 'Main menu' }).click()
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')

  await page
    .locator('button[name="menu\\[drop_items_ids\\]\\[\\]"]')
    .first()
    .click()
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/navigation/menus')
  await syncLV(page)

  await page.goto('/')
  await expect(
    page.locator('[data-menu-item-key="brando"]').getByText('Brando CMS')
  ).not.toBeVisible()
})

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
