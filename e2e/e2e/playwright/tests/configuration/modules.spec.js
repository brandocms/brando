import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function openNewModule(page) {
  await page.goto('/admin/config/content/modules')
  await page.getByRole('button', { name: 'Create new' }).click()
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Edit module' })).toBeVisible()
}

// The module editor splits its form across tabs; a panel's fields are hidden
// until its tab is selected.
// Retry until the tab is genuinely selected: a click that lands while the
// LiveView is patching (e.g. right after a var delete re-renders the form) is
// swallowed, and `to_tab/1` silently falls back to :template.
async function openModuleTab(page, name) {
  const tab = page.getByRole('tab', { name: new RegExp(`^${name}`) })
  await expect(async () => {
    await tab.click()
    await expect(tab).toHaveAttribute('aria-selected', 'true')
  }).toPass({ timeout: 15000 })
  await syncLV(page)
}

// Var chips expose their actions only on hover: `.var-chip-actions` is
// `opacity: 0; pointer-events: none` until `.var-chip:hover`. If :hover is not
// active at the instant of the click, the click passes straight through to the
// chip body and nothing happens — silently, with no error. So verify the
// outcome and retry, checking first each round so a click that did land is
// never repeated (re-running a duplicate would create theme_copy_copy).
async function clickVarChipAction(page, label, outcome) {
  const button = page.getByRole('button', { name: label, exact: true })
  const chip = page.locator('.var-chip').filter({ has: button })
  for (let attempt = 0; attempt < 5; attempt++) {
    if (await outcome().then(() => true, () => false)) return
    await chip.hover()
    await button.click().catch(() => {})
    await page.waitForTimeout(400)
  }
  await outcome()
}

async function replaceModuleCode(page, code) {
  await openModuleTab(page, 'Template')
  await page.click('.cm-editor')
  await page.keyboard.down('ControlOrMeta')
  await page.keyboard.press('A')
  await page.keyboard.up('ControlOrMeta')
  await page.keyboard.press('Backspace')
  await page.keyboard.type(code)
}

test('create a simple text module', async ({ page }) => {
  await openNewModule(page)

  await openModuleTab(page, 'Overview')
  await page.locator('input[name="module[name][en]"]').fill('New text module')
  await page.locator('input[name="module[namespace][en]"]').fill('general')
  await page.locator('textarea[name="module[help_text][en]"]').fill('Helpful text')

  await openModuleTab(page, 'References')
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

  await openModuleTab(page, 'Variables')
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

  await clickVarChipAction(page, 'Duplicate variable theme', async () => {
    await expect(
      page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })
    ).toHaveCount(1, { timeout: 2000 })
  })
  varModal = page.locator('#module-default-var-0')
  await expect(varModal.getByLabel('Key', { exact: true })).toHaveValue('theme_copy')
  await expect(
    varModal.locator('input[name*="[options]"][name$="[label]"]').filter({ visible: true })
  ).toHaveValue('Dark')
  await expect(
    varModal.locator('input[name*="[options]"][name$="[value]"]').filter({ visible: true })
  ).toHaveValue('dark')
  await varModal.getByRole('button', { name: 'Done' }).click()

  await openModuleTab(page, 'References')
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

  await openModuleTab(page, 'Variables')
  await expect(page.getByRole('button', { name: 'Edit variable theme', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })).toBeVisible()
  await openModuleTab(page, 'References')
  await expect(page.getByRole('button', { name: 'Edit reference intro_text', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit reference intro_text_copy', exact: true })).toBeVisible()

  await openModuleTab(page, 'Variables')
  page.on('dialog', (dialog) => dialog.accept())
  await clickVarChipAction(page, 'Delete variable theme_copy', async () => {
    await expect(
      page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })
    ).toHaveCount(0, { timeout: 2000 })
  })
  // The `page.on` handler above stays registered and covers this confirm too.
  await openModuleTab(page, 'References')
  await page.getByRole('button', { name: 'Delete reference intro_text_copy', exact: true }).click()

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await page.getByRole('link', { name: 'New module →' }).click()
  await syncLV(page)

  await openModuleTab(page, 'Variables')
  await expect(page.getByRole('button', { name: 'Edit variable theme', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit variable theme_copy', exact: true })).toHaveCount(0)
  await openModuleTab(page, 'References')
  await expect(page.getByRole('button', { name: 'Edit reference intro_text', exact: true })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Edit reference intro_text_copy', exact: true })).toHaveCount(0)
})
