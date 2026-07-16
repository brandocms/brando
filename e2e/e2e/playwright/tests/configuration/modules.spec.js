import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function openNewModule(page) {
  await page.goto('/admin/config/content/modules')
  await page.getByRole('button', { name: 'Create new' }).click()
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Edit module' })).toBeVisible()
}

async function replaceModuleCode(page, code) {
  await page.click('.cm-editor')
  await page.keyboard.down('ControlOrMeta')
  await page.keyboard.press('A')
  await page.keyboard.up('ControlOrMeta')
  await page.keyboard.press('Backspace')
  await page.keyboard.type(code)
}

test('create a simple text module', async ({ page }) => {
  await openNewModule(page)

  await page.locator('input[name="module[name][en]"]').fill('New text module')
  await page.locator('input[name="module[namespace][en]"]').fill('general')
  await page.locator('textarea[name="module[help_text][en]"]').fill('Helpful text')

  await page.getByRole('button', { name: 'Add reference' }).click()
  await page.getByRole('button', { name: 'Text Rich, editable body content' }).click()

  const refModal = page.locator('#module-default-ref-0')
  await expect(refModal).toBeVisible()
  await refModal.getByLabel('Template name').fill('text')
  await refModal.getByLabel('Text', { exact: true }).fill('<p>Tekst</p>')
  await refModal.getByRole('button', { name: 'Done' }).click()

  await replaceModuleCode(page, '{% ref refs.text %}')
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL('/admin/config/content/modules')
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'New text module →', exact: true })).toBeVisible()
  await expect(page.getByText('Helpful text', { exact: true })).toBeVisible()
})

test('create, edit, duplicate, persist and delete refs and vars', async ({ page }) => {
  await openNewModule(page)

  await page.getByRole('button', { name: 'Add variable' }).click()
  await page
    .getByRole('button', { name: 'Select A choice from predefined options' })
    .click()

  let varModal = page.locator('#module-default-var-0')
  await expect(varModal).toBeVisible()
  await varModal.getByLabel('Key', { exact: true }).fill('theme')
  await varModal.getByLabel('Label', { exact: true }).fill('Theme')
  await varModal.getByRole('button', { name: 'Add option' }).click()
  await varModal
    .locator('input[name*="[options]"][name$="[label]"]')
    .filter({ visible: true })
    .fill('Dark')
  await varModal
    .locator('input[name*="[options]"][name$="[value]"]')
    .filter({ visible: true })
    .fill('dark')
  await varModal.getByRole('button', { name: 'Done' }).click()

  await page.getByRole('button', { name: 'Duplicate variable theme' }).click()
  varModal = page.locator('#module-default-var-0')
  await expect(varModal.getByLabel('Key', { exact: true })).toHaveValue('theme_copy')
  await expect(
    varModal.locator('input[name*="[options]"][name$="[label]"]').filter({ visible: true })
  ).toHaveValue('Dark')
  await expect(
    varModal.locator('input[name*="[options]"][name$="[value]"]').filter({ visible: true })
  ).toHaveValue('dark')
  await varModal.getByRole('button', { name: 'Done' }).click()

  await page.getByRole('button', { name: 'Add reference' }).click()
  await page.getByRole('button', { name: 'Text Rich, editable body content' }).click()

  let refModal = page.locator('#module-default-ref-0')
  await expect(refModal).toBeVisible()
  await refModal.getByLabel('Template name').fill('intro_text')
  await refModal.getByLabel('Editor description').fill('Editable introduction')
  await refModal.getByLabel('Text', { exact: true }).fill('<p>Intro text</p>')
  await refModal.getByRole('button', { name: 'Done' }).click()

  await page.getByRole('button', { name: 'Duplicate reference intro_text' }).click()
  refModal = page.locator('#module-default-ref-0')
  await expect(refModal.getByLabel('Template name')).toHaveValue('intro_text_copy')
  await expect(refModal.getByLabel('Editor description')).toHaveValue('Editable introduction')
  await expect(refModal.getByLabel('Text', { exact: true })).toHaveValue('<p>Intro text</p>')
  await refModal.getByRole('button', { name: 'Done' }).click()

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await page.getByRole('link', { name: 'New module →' }).click()
  await syncLV(page)

  await expect(page.getByRole('button', { name: 'Edit variable theme', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit reference intro_text', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit reference intro_text_copy', exact: true })).toBeVisible()

  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete variable theme_copy', exact: true }).click()
  page.once('dialog', (dialog) => dialog.accept())
  await page.getByRole('button', { name: 'Delete reference intro_text_copy', exact: true }).click()

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await page.getByRole('link', { name: 'New module →' }).click()
  await syncLV(page)

  await expect(page.getByRole('button', { name: 'Edit variable theme', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Edit reference intro_text', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit reference intro_text_copy', exact: true })).toHaveCount(0)
})
