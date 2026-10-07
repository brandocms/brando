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

// Chromium's virtual authenticator stands in for a phone or a fingerprint
// reader: it makes and uses passkeys without asking.
const virtualAuthenticator = async (page) => {
  const client = await page.context().newCDPSession(page)
  await client.send('WebAuthn.enable')
  const { authenticatorId } = await client.send('WebAuthn.addVirtualAuthenticator', {
    options: {
      protocol: 'ctap2',
      transport: 'internal',
      hasResidentKey: true,
      hasUserVerification: true,
      isUserVerified: true,
      automaticPresenceSimulation: true,
    },
  })
  return { client, authenticatorId }
}

// GET /admin/logout only asks; its button signs out (a DELETE)
const logOut = async (page) => {
  await page.goto('/admin/logout')
  await syncLV(page)
  await page.getByTestId('logout-confirm').click()
  await expect(page).toHaveURL('/admin/login')
}

const logIn = async (page, email, password) => {
  await page.goto('/admin/login')
  await syncLV(page)
  await page.getByTestId('email').fill(email)
  await page.getByTestId('password').fill(password)
  await page.getByTestId('login-button').click()
}

test('a user adds a passkey, logs in with it alone, and as the second step', async ({ browser, sandboxUserAgent }, testInfo) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const page = await context.newPage()

  try {
    const { client, authenticatorId } = await virtualAuthenticator(page)
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin')

    await page.goto('/admin/users/security')
    await syncLV(page)
    await page.getByTestId('passkey-add').click()
    const modal = page.locator('#passkey-add-modal')
    await expect(modal).toBeVisible()
    await modal.getByTestId('passkey-name').fill('Work laptop')
    // A session alone does not add a passkey
    await modal.getByTestId('passkey-proof').fill('not my password')
    await modal.getByTestId('passkey-create').click()
    await expect(modal.getByTestId('passkey-error')).toBeVisible()
    const { credentials: none } = await client.send('WebAuthn.getCredentials', { authenticatorId })
    expect(none).toHaveLength(0)

    await modal.getByTestId('passkey-proof').fill(password)
    await page.screenshot({ path: testInfo.outputPath('add-passkey.png') })
    await modal.getByTestId('passkey-create').click()

    // The first second factor comes with recovery codes
    await expect(page.locator('#recovery-codes-modal').getByTestId('recovery-code')).toHaveCount(10)
    await page.getByTestId('recovery-codes-done').click()
    await expect(page.getByTestId('passkey')).toHaveCount(1)
    await expect(page.getByTestId('passkey')).toContainText('Work laptop')
    await expect(page.getByTestId('two-factor-status')).toHaveAttribute('data-enabled', 'true')
    const { credentials } = await client.send('WebAuthn.getCredentials', { authenticatorId })
    expect(credentials).toHaveLength(1)

    // A passkey alone logs in
    await logOut(page)
    await page.goto('/admin/login')
    await syncLV(page)
    await page.getByTestId('login-passkey').click()
    await expect(page).toHaveURL('/admin')

    // After the password, the passkey is the second step
    await logOut(page)
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin/login/two-factor')
    await syncLV(page)
    await page.screenshot({ path: testInfo.outputPath('second-step.png') })
    await page.getByTestId('two-factor-passkey').click()
    await expect(page).toHaveURL('/admin')

    // Where the user is logged in
    await page.goto('/admin/users/security')
    await syncLV(page)
    await expect(page.locator('[data-testid=session][data-current=true]')).toHaveCount(1)
  } finally {
    await context.close()
  }
})

test('a sensitive action asks for the password again after a while', async ({ browser, sandboxUserAgent }) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const page = await context.newPage()

  try {
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin')
    await fixture(sandboxUserAgent, 'stale-sessions', { email })

    await page.goto('/admin/users/security')
    await syncLV(page)
    await page.getByTestId('passkey-add').click()
    const prompt = page.locator('#reauth-modal')
    await expect(prompt).toBeVisible()
    await expect(page.locator('#passkey-add-modal')).toHaveCount(0)

    await prompt.getByTestId('reauth-proof').fill('not my password')
    await prompt.getByTestId('reauth-submit').click()
    await expect(prompt.getByTestId('reauth-error')).toBeVisible()

    await prompt.getByTestId('reauth-proof').fill(password)
    await prompt.getByTestId('reauth-submit').click()
    await expect(page.locator('#reauth-modal')).toHaveCount(0)
    // The action it held goes ahead
    await expect(page.locator('#passkey-add-modal')).toBeVisible()
  } finally {
    await context.close()
  }
})

test('a screen that needs it sends a stale session to confirm first, and back', async ({ page, sandboxUserAgent }) => {
  await fixture(sandboxUserAgent, 'stale-sessions', { email: 'admin@brandocms.com' })

  await page.goto('/admin/users/sign-in-policy')
  await expect(page).toHaveURL(/\/admin\/confirm\?return_to=/)
  await syncLV(page)
  await page.getByTestId('reauth-proof').fill('brandocms')
  await page.getByTestId('reauth-submit').click()
  await expect(page).toHaveURL('/admin/users/sign-in-policy')
})
