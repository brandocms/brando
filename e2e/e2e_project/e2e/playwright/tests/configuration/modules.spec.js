import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('create a simple text module', async ({ page }) => {
  await page.goto('/admin')

  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'Block modules' }).click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await page.getByRole('button', { name: 'Create new' }).click()
  await syncLV(page)
  await page.locator('input[name="module[name][no]"]').fill('Ny modul')
  await page.locator('input[name="module[namespace][no]"]').fill('generell')
  await page
    .locator('textarea[name="module[help_text][no]"]')
    .fill('Hjelpetekst')
  await page.getByRole('heading', { name: 'REFs' }).getByRole('button').click()
  await page.getByRole('button', { name: 'Text' }).click()
  await page
    .locator('li')
    .filter({ hasText: 'text - %{' })
    .getByRole('button')
    .first()
    .click()
  await page.getByLabel('Name').click()
  await page.getByLabel('Text').fill('<p>Tekst</p>')
  await page
    .locator('#module_refs_0_data_data_extensions-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: '— Paragraph' }).click()
  await page.getByRole('button', { name: '— H2' }).click()
  await page.getByRole('button', { name: '— Link' }).click()
  await page.getByRole('button', { name: 'OK' }).click()
  await page
    .locator('header')
    .filter({ hasText: 'Edit ref' })
    .getByRole('button')
    .click()

  await page.click('.cm-editor')
  await page.keyboard.down('ControlOrMeta')
  await page.keyboard.press('A')
  await page.keyboard.up('ControlOrMeta')
  await page.keyboard.press('Backspace')
  await page.keyboard.type('{% ref refs.text %}')

  await syncLV(page)
  await page.getByTestId('submit').click()
  await syncLV(page)
  await expect(page).toHaveURL('/admin/config/content/modules')
  await expect(page.getByRole('link', { name: 'New module →' })).toBeVisible()
  await expect(page.getByText('Help text')).toBeVisible()
})
