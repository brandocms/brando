import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Field inputs are named form[fields][<index>][<field>]; the edit modal of the
// field being edited is the visible one.
const modal = page => page.locator('.modal:visible')
const modalInput = (page, field) => modal(page).locator(`input[id^="form_fields_"][id$="_${field}"]`)
const chip = (page, key) => page.locator('.form-fields-designer .var-chip').filter({ has: page.locator('.var-chip-key', { hasText: new RegExp(`^\\s*${key}\\*?\\s*$`) }) })

const addField = async (page, type, { key, label }) => {
  await page.locator('.form-fields-quick-add').getByRole('button', { name: type, exact: true }).click()
  await expect(modal(page)).toBeVisible()
  if (key) await modalInput(page, 'key').fill(key)
  await modalInput(page, 'label').fill(label)
  await syncLV(page)
}

const closeModal = async page => {
  await modal(page).getByRole('button', { name: 'Done' }).click()
  await expect(modal(page)).toHaveCount(0)
}

test('build a form, then translate it', async ({ page }) => {
  const key = `contact_${Date.now()}`

  // Forms are built under Configuration; the content menu only lists what they receive
  await page.goto('/admin')
  await expect(page.locator('a[href="/admin/forms"]')).toHaveCount(0)
  await page.getByText('Configuration').click()
  await page.locator('a[href="/admin/config/forms"]').click()
  await expect(page).toHaveURL('/admin/config/forms')
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)

  await page.locator('input[name="form[title]"]').fill(key)
  await page.locator('input[name="form[key]"]').fill(key)

  await addField(page, 'Text', { key: 'name', label: 'Full name' })
  await closeModal(page)
  await addField(page, 'Email', { label: 'Email' })
  await closeModal(page)

  // Side by side, half a row each
  for (const field of ['name', 'email']) {
    await chip(page, field).locator('.var-width-group').getByRole('button', { name: '1/2' }).click()
    await syncLV(page)
  }
  await chip(page, 'name').getByRole('button', { name: 'req' }).click()
  await syncLV(page)

  await addField(page, 'Dropdown', { key: 'service', label: 'Service' })
  await modal(page).locator('input[name$="[option_rows][0][label]"]').fill('Website')
  await modal(page).locator('input[name$="[option_rows][1][label]"]').fill('Brand identity')
  await syncLV(page)
  await closeModal(page)

  const preview = page.locator('.form-fields-preview')
  await expect(preview.locator('.site-form-field[data-key="name"][data-width="half"] input[required]')).toBeVisible()
  await expect(preview.locator('.site-form-field[data-key="service"] option[value="option_1"]')).toHaveText('Website')

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/forms')
  await syncLV(page)

  await page.getByRole('link', { name: key }).click()
  await syncLV(page)
  const rows = page.locator('.form-fields-designer .var-layout-row')
  await expect(rows.nth(0).locator('.var-chip')).toHaveCount(2)
  await expect(chip(page, 'name').locator('.form-field-required')).toBeVisible()
  await expect(chip(page, 'service')).toBeVisible()

  // A translation follows the source's fields and only words them
  const sourceUrl = page.url()
  await page.locator('.translation-panel').getByRole('button', { name: 'Norwegian' }).click()
  await page.waitForURL(url => url.href !== sourceUrl)
  await syncLV(page)
  await expect(page.locator('.form-fields-designer[data-locked]')).toBeVisible()
  await expect(page.getByRole('button', { name: 'Add field' })).toHaveCount(0)

  await chip(page, 'service').locator('.var-chip-label').click()
  await expect(modal(page).locator('.form-field-locked')).toBeVisible()
  await expect(modal(page).locator('input[name$="[option_rows][0][value]"]')).toHaveAttribute('readonly', '')
  await modalInput(page, 'label').fill('Tjeneste')
  await modal(page).locator('input[name$="[option_rows][0][label]"]').fill('Nettside')
  await syncLV(page)
  await closeModal(page)
  await expect(preview.locator('.site-form-field[data-key="service"] option[value="option_1"]')).toHaveText('Nettside')

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/forms')

  // With a form built, the content menu lists what it receives
  await page.goto('/admin')
  await page.locator('a[href="/admin/forms"]').click()
  await expect(page).toHaveURL('/admin/forms')
  await syncLV(page)
  await expect(page.locator(`#form-inbox-${key}`)).toContainText(key)
})
