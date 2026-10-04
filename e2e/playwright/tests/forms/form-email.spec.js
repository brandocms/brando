import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The published contact form of E2EFixtureController `site-form`, held by the
// page "Contact" at /contact-us.
test.beforeEach(async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/site-form')
  expect(response.ok()).toBeTruthy()
})

const openForm = async page => {
  await page.goto('/admin/config/forms')
  await syncLV(page)
  await page.getByRole('link', { name: 'Contact us' }).click()
  await syncLV(page)
}

const tab = (page, name) => page.locator('.form-tab-customs').getByRole('button', { name, exact: true })

const save = async page => {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/forms')
}

const send = async page => {
  await page.goto('/contact-us')
  const form = page.locator('form#form-contact')
  await form.getByLabel('Name').fill('Ada Lovelace')
  await form.getByLabel('Email').fill('ada@example.com')
  await form.getByRole('button', { name: 'Send' }).click()
}

test('an editor sets who a form emails, and sends a submission again', async ({ page }) => {
  await openForm(page)
  // The form's screen names the page holding it
  await expect(page.locator('.usage-list')).toContainText('Contact')

  await tab(page, 'Submissions').click()
  const recipients = page.locator('[data-sortable-id="form[recipients]-sortable"]')
  await page.locator('.subform--table').filter({ has: recipients }).getByRole('button', { name: 'Add entry' }).click()
  await syncLV(page)
  await recipients.locator('input[name$="[name]"]').fill('Post')
  await recipients.locator('input[name$="[email]"]').fill('post@example.com')
  await page.locator('input[name="form[subject]"]').fill('Message from {{ name }}')
  await syncLV(page)
  await save(page)

  await send(page)
  await expect(page.locator('#form-contact-sent')).toBeVisible()

  await page.goto('/admin/forms/contact/submissions')
  await syncLV(page)
  const row = page.locator('.form-submissions-table tbody tr').first()
  await expect(row.locator('.form-submission-email.is-sent')).toBeVisible()

  await row.getByRole('button', { name: 'Open' }).click()
  const detail = page.locator('#submission-detail')
  await expect(detail.locator('.form-submission-email.is-sent')).toBeVisible()
  await detail.getByRole('button', { name: 'Send again' }).click()
  await syncLV(page)
  await expect(row.locator('.form-submission-email.is-sent')).toBeVisible()
})

test('a form sends visitors on to its page once it is sent', async ({ page }) => {
  await openForm(page)
  await tab(page, 'Messages').click()
  await page.locator('input[name="form[redirect_url]"]').fill('/thank-you')
  await syncLV(page)
  await save(page)

  await send(page)
  await expect(page).toHaveURL(/\/thank-you$/)
})
