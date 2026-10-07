import { test, expect } from '../../test-support/setupAuth'
import { baseURL, e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// The fixtures run in this test's SQL sandbox, picked by the user agent.
const fixture = async (userAgent, action, body = {}) => {
  const response = await fetch(e2eUrl(`/e2e/password-reset/${action}`), {
    method: 'POST',
    headers: { 'user-agent': userAgent, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  expect(response.ok).toBe(true)
  return response.json()
}

const resetLink = async (userAgent, email) => {
  let text
  await expect.poll(async () => {
    text = (await fixture(userAgent, 'mailbox', { to: email })).text
    return text
  }).toContain('/admin/reset-password/')
  return new URL(text.match(/https?:\/\/\S+\/admin\/reset-password\/[A-Za-z0-9_-]+/)[0]).pathname
}

test('a user who forgot their password resets it by email and logs in', async ({ browser, sandboxUserAgent }, testInfo) => {
  const { email } = await fixture(sandboxUserAgent, 'user')
  // Logged out, in this test's sandbox
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const page = await context.newPage()

  try {
    await page.goto('/admin/login')
    await syncLV(page)
    await page.getByTestId('forgot-password').click()
    await expect(page).toHaveURL('/admin/reset-password')
    await syncLV(page)

    // The screens before login are in the default admin language; an
    // address without an account gets the same answer as one with
    await page.getByTestId('email').fill('nobody@brandocms.com')
    await page.getByTestId('send-reset-link').click()
    await expect(page.locator('#reset_password_sent .alert')).toContainText('nobody@brandocms.com')
    const unknown = await page.locator('#reset_password_sent .alert').textContent()

    await page.goto('/admin/reset-password')
    await syncLV(page)
    await page.getByTestId('email').fill(email)
    await page.getByTestId('send-reset-link').click()
    await expect(page.locator('#reset_password_sent .alert')).toContainText(email)
    const known = await page.locator('#reset_password_sent .alert').textContent()
    expect(known.replace(email, '')).toBe(unknown.replace('nobody@brandocms.com', ''))
    await page.screenshot({ path: testInfo.outputPath('reset-sent.png') })

    const link = await resetLink(sandboxUserAgent, email)
    await page.goto(link)
    await syncLV(page)
    await expect(page.locator('#new_password_form')).toContainText(email)

    await page.getByLabel('New password', { exact: true }).fill('a brand new password')
    await page.getByLabel('Confirm new password').fill('something else')
    await page.getByTestId('save-password').click()
    await expect(page.locator('#new_password_form')).toContainText('does not match')
    await page.screenshot({ path: testInfo.outputPath('reset-mismatch.png') })

    await page.getByLabel('Confirm new password').fill('a brand new password')
    await page.getByTestId('save-password').click()
    await expect(page).toHaveURL('/admin/login')
    await expect(page.locator('#login_form .alert')).toBeVisible()

    // The link worked once
    await page.goto(link)
    await expect(page).toHaveURL('/admin/reset-password')
    await expect(page.locator('#reset_password_form .alert.danger')).toBeVisible()

    await page.goto('/admin/login')
    await syncLV(page)
    await page.getByTestId('email').fill(email)
    await page.getByTestId('password').fill('a brand new password')
    await page.getByTestId('login-button').click()
    await expect(page).toHaveURL('/admin')
  } finally {
    await context.close()
  }
})

test('a superuser sends an editor a reset link from the user form', async ({ page, sandboxUserAgent }) => {
  const { email } = await fixture(sandboxUserAgent, 'user')

  await page.goto('/admin/users')
  await syncLV(page)
  await page.locator('.content-list .list-row').filter({ hasText: email }).getByRole('link', { name: 'Reset Editor' }).click()
  await syncLV(page)

  await expect(page.locator('input[name="user[password]"]')).toHaveCount(0)
  await page.getByTestId('send-password-reset').click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toContainText('Send a password reset link?')
  await dialog.getByRole('button', { name: 'Send link' }).click()
  await syncLV(page)

  await expect.poll(async () => (await fixture(sandboxUserAgent, 'mailbox', { to: email })).text)
    .toContain('An administrator sent you this link')
})
