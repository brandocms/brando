import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { baseURL } from '../../test-support/e2eUrl'

// A published contact form in a page block (E2EFixtureController `site-form`).
// The page serves stored block HTML, so these also cover the CSRF token being
// filled in per request.
test.beforeEach(async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/site-form')
  expect(response.ok()).toBeTruthy()
})

test('a visitor sends the form and an editor reads it', async ({ page }) => {
  await page.goto('/contact-us')
  const form = page.locator('form#form-contact')
  await expect(form.locator('input[name="_csrf_token"]')).not.toHaveValue('$csrftoken')
  // As a cache in front of the site would serve it: someone else's token, which the script replaces
  await form.locator('input[name="_csrf_token"]').evaluate(input => { input.value = 'cached-for-someone-else' })

  // Sent empty: the required fields are marked where they are
  await form.locator('input[name="fields[name]"]').evaluate(input => input.removeAttribute('required'))
  await form.locator('input[name="fields[email]"]').evaluate(input => input.removeAttribute('required'))
  await form.getByRole('button', { name: 'Send' }).click()
  await expect(form.locator('input[name="fields[email]"]')).toHaveAttribute('aria-invalid', 'true')
  await expect(form.locator('.site-form-field[data-key="name"] .site-form-error')).toBeVisible()

  await form.getByLabel('Name').fill('Ada Lovelace')
  await form.getByLabel('Email').fill('ada@example.com')
  await form.getByLabel('Message').fill('About the engine')
  await form.getByRole('button', { name: 'Send' }).click()

  await expect(page.locator('#form-contact-sent')).toBeVisible()
  await expect(form.locator('.site-form-actions')).toBeHidden()

  await page.goto('/admin/forms')
  await syncLV(page)
  await page.locator('#form-inbox-contact').getByRole('link', { name: 'Open' }).click()
  await expect(page).toHaveURL('/admin/forms/contact/submissions')
  await syncLV(page)
  const row = page.locator('.form-submissions-table tbody tr').first()
  await expect(row).toContainText('Ada Lovelace')
  await row.getByRole('button', { name: 'Open' }).click()
  await expect(page.locator('#submission-detail')).toContainText('About the engine')
})

test('without JavaScript a post lands back on the page at its message', async ({ page, browser }) => {
  const userAgent = await page.evaluate(() => navigator.userAgent)
  // Same sandbox user agent, so the post reaches this test's data
  const context = await browser.newContext({ baseURL, userAgent, javaScriptEnabled: false })
  const visitor = await context.newPage()

  await visitor.goto('/contact-us')
  await visitor.getByLabel('Name').fill('Grace Hopper')
  await visitor.getByLabel('Email').fill('grace@example.com')
  await visitor.getByRole('button', { name: 'Send' }).click()

  await expect(visitor).toHaveURL(/\/contact-us#form-contact-sent$/)
  await expect(visitor.locator('#form-contact-sent')).toBeVisible()
  await expect(visitor.locator('#form-contact-failed')).toBeHidden()
  await context.close()
})

// The site's wording for form messages: messages_live_test.exs edits it,
// and submission_controller_test.exs checks the reply the page shows.
