import { test, expect } from '../../test-support/setupAuth'
import { e2eUrl } from '../../test-support/e2eUrl'
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

// Forgetting a password and resetting it by email, and a superuser setting
// one, are LiveView and controller tests (password_reset_live_test.exs). This
// one stays for the titled confirmation dialog the reset link goes through.

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
