import { test, expect } from '../../test-support/setupAuth'
import { baseURL, e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// The fixtures run in this test's SQL sandbox, picked by the user agent.
const fixture = async (userAgent, action, body = {}) => {
  const response = await fetch(e2eUrl(`/e2e/two-factor/${action}`), {
    method: 'POST',
    headers: { 'user-agent': userAgent, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  expect(response.ok).toBe(true)
  return response.json()
}

const logIn = async (page, email, password) => {
  await page.goto('/admin/login')
  await syncLV(page)
  await page.getByTestId('email').fill(email)
  await page.getByTestId('password').fill(password)
  await page.getByTestId('login-button').click()
  await expect(page).toHaveURL('/admin')
}

test('the account menu signs out', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  await page.getByTestId('current-user').click()
  await page.getByTestId('logout').click()
  await expect(page).toHaveURL('/admin/login')

  await page.goto('/admin')
  await expect(page).toHaveURL('/admin/login')
})

test('GET /admin/logout only asks, and nothing else signs out', async ({ page }) => {
  // Neither a plain GET nor a DELETE without the CSRF token, as another site could send
  expect((await page.request.get('/admin/logout')).ok()).toBe(true)
  expect((await page.request.delete('/admin/logout', { maxRedirects: 0 })).status()).toBe(403)

  await page.goto('/admin/logout')
  await syncLV(page)
  await page.getByTestId('logout-cancel').click()
  await expect(page).toHaveURL('/admin')

  await page.goto('/admin/logout')
  await syncLV(page)
  await page.getByTestId('logout-confirm').click()
  await expect(page).toHaveURL('/admin/login')
  await page.goto('/admin')
  await expect(page).toHaveURL('/admin/login')
})

test('logging out a session from another browser closes its open admin', async ({ browser, sandboxUserAgent }) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')
  const first = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const second = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })

  try {
    const open = await first.newPage()
    await logIn(open, email, password)
    await syncLV(open)

    const other = await second.newPage()
    await logIn(other, email, password)
    await other.goto('/admin/users/security')
    await syncLV(other)
    await other.locator('[data-testid=session][data-current=false]').getByTestId('session-revoke').click()
    await expect(other.getByTestId('session')).toHaveCount(1)

    // Disconnected, the open page goes back to log in by itself
    await expect(open).toHaveURL('/admin/login', { timeout: 15000 })

    // The other browser is still in
    await other.goto('/admin')
    await expect(other).toHaveURL('/admin')
  } finally {
    await first.close()
    await second.close()
  }
})
