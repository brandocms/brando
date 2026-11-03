// playwright/tests/my-test.spec.ts
import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// test.use({ scenario: 'admin-user' })

test('update identity', async ({ page }) => {
  // Go to the /admin page
  await page.goto('/admin')

  // Wait for navigation and check that the URL is /admin/login
  await expect(page).toHaveURL('/admin')
  // The sticky nav joins after the page: a click on its server render is lost
  await syncLV(page)

  await page.getByText('Configuration').click()
  await page.getByText('Identity').click()

  await expect(page).toHaveURL('/admin/config/identity')

  await page.getByLabel('Name', { exact: true }).fill('Acme Organization')
  await page.getByLabel('Alternate name', { exact: true }).fill('Acme Org')
  await page.getByLabel('Email', { exact: true }).fill('info@acme.com')
  await page.getByLabel('Phone', { exact: true }).fill('+47 987 65 432')
  await page.getByLabel('Address line 1', { exact: true }).fill('Acme Street 1')
  await page.getByLabel('Address line 2', { exact: true }).fill('Walkup 1')
  await page.getByLabel('City', { exact: true }).fill('Oslo')
  await page.getByLabel('Zip code', { exact: true }).fill('0101')
  await page.getByLabel('Title (prefix)', { exact: true }).fill('Acme // ')
  await page.getByLabel('Title', { exact: true }).fill('Hello!')

  await page
    .locator('#identity_links-field-base')
    .getByRole('button', { name: 'Add entry' })
    .click()

  await page.locator('#identity_links_0_name').fill('Instagram')
  await page.locator('#identity_links_0_url').fill('https://instagram.com/acme')

  await page
    .locator('#identity_links-field-base')
    .getByRole('button', { name: 'Add entry' })
    .click()

  await page.locator('#identity_links_1_name').fill('Facebook')
  await page.locator('#identity_links_1_url').fill('https://facebook.com/acme')

  await page
    .locator('#identity_links-field-base')
    .getByRole('button', { name: 'Add entry' })
    .click()

  await page.locator('#identity_links_2_name').fill('Twitter')
  await page.locator('#identity_links_2_url').fill('https://twitter.com/acme')

  await syncLV(page)

  await page
    .locator('button[name="identity\\[drop_links_ids\\]\\[\\]"]')
    .nth(1)
    .click()

  // The save has landed when the form's save state goes from dirty to clean
  const saveState = page.locator('.draft-save-state').first()
  await expect(saveState).toHaveAttribute('data-state', 'dirty')
  await page.getByTestId('submit').click()
  await expect(saveState).toHaveAttribute('data-state', 'clean', { timeout: 15000 })

  await page.goto('/')
  await expect(page).toHaveTitle('Acme // Index')
  let metaTagLocator = page.locator(
    'meta[property="og:see_also"][content="https://twitter.com/acme"]'
  )
  await expect(metaTagLocator).toHaveCount(1)
  metaTagLocator = page.locator(
    'meta[property="og:see_also"][content="https://instagram.com/acme"]'
  )
  await expect(metaTagLocator).toHaveCount(1)
})
