import { test, expect } from '../../test-support/setupAuth'
import { baseURL, e2eUrl } from '../../test-support/e2eUrl'
import { totp } from '../../test-support/totp'
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

// A browser of its own, logged out, in this test's sandbox
const loggedOut = async (browser, userAgent) => {
  const context = await browser.newContext({ baseURL, userAgent })
  return { context, page: await context.newPage() }
}

const logIn = async (page, email, password) => {
  await page.goto('/admin/login')
  await syncLV(page)
  await page.getByTestId('email').fill(email)
  await page.getByTestId('password').fill(password)
  await page.getByTestId('login-button').click()
}

const enterCode = async (page, code) => {
  await expect(page).toHaveURL('/admin/login/two-factor')
  await syncLV(page)
  await page.getByTestId('two-factor-code').fill(code)
  await page.getByTestId('two-factor-submit').click()
}

test('a user sets up two-factor authentication, then logs in with a code', async ({ browser, sandboxUserAgent }, testInfo) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')
  const { context, page } = await loggedOut(browser, sandboxUserAgent)

  try {
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin')

    // From the account menu
    await page.goto('/admin/users/security')
    await syncLV(page)
    await expect(page.getByTestId('two-factor-status')).toHaveAttribute('data-enabled', 'false')
    await page.getByTestId('two-factor-setup').click()
    const modal = page.locator('#two-factor-setup-modal')
    await expect(modal.locator('.two-factor-qr svg')).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('setup.png') })

    const secret = (await modal.getByTestId('two-factor-secret').textContent()).trim()
    await modal.getByTestId('two-factor-setup-code').fill('000000')
    await modal.getByTestId('two-factor-enable').click()
    await expect(modal.locator('.two-factor-error')).toBeVisible()

    await modal.getByTestId('two-factor-setup-code').fill(totp(secret))
    await modal.getByTestId('two-factor-enable').click()
    const codes = page.locator('#recovery-codes-modal').getByTestId('recovery-code')
    await expect(codes).toHaveCount(10)
    await page.screenshot({ path: testInfo.outputPath('recovery-codes.png') })
    await page.getByTestId('recovery-codes-done').click()
    await expect(page.getByTestId('two-factor-status')).toHaveAttribute('data-enabled', 'true')
    await expect(page.getByTestId('security-events').locator('[data-action="two_factor_enabled"]')).toBeVisible()

    // The password alone is not enough any more
    await page.goto('/admin/logout')
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin/login/two-factor')
    await page.goto('/admin/users')
    await expect(page).toHaveURL('/admin/login')

    await logIn(page, email, password)
    await enterCode(page, '000000')
    await expect(page.locator('#two_factor_form .alert.danger')).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('wrong-code.png') })

    // The setup used up this step's code: the app's next one works, and
    // goes on to where they were going
    await enterCode(page, totp(secret, 1))
    await expect(page).toHaveURL('/admin/users')
  } finally {
    await context.close()
  }
})

test('a user who lost their phone logs in with a recovery code, once', async ({ browser, sandboxUserAgent }) => {
  const { email, password, codes } = await fixture(sandboxUserAgent, 'enabled-user')
  const { context, page } = await loggedOut(browser, sandboxUserAgent)

  try {
    await logIn(page, email, password)
    await enterCode(page, codes[0].toUpperCase())
    await expect(page).toHaveURL('/admin')

    await page.goto('/admin/users/security')
    await syncLV(page)
    await expect(page.getByTestId('recovery-codes-left')).toContainText('9')

    await page.goto('/admin/logout')
    await logIn(page, email, password)
    await enterCode(page, codes[0])
    await expect(page).toHaveURL('/admin/login/two-factor')
    await expect(page.locator('#two_factor_form .alert.danger')).toBeVisible()

    await enterCode(page, codes[1])
    await expect(page).toHaveURL('/admin')
  } finally {
    await context.close()
  }
})

test('the sign-in policy makes an editor set two-factor authentication up at their next login', async ({ page, browser, sandboxUserAgent }, testInfo) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')

  // A superuser requires it of editors
  await page.goto('/admin/users')
  await syncLV(page)
  await page.locator('a[href="/admin/users/sign-in-policy"]').click()
  await expect(page).toHaveURL('/admin/users/sign-in-policy')
  await syncLV(page)
  await page.getByTestId('policy-selected').check()
  await syncLV(page)
  await page.getByTestId('policy-option-editor').check()
  await syncLV(page)
  await page.getByTestId('policy-save').click()
  await syncLV(page)
  await page.reload()
  await syncLV(page)
  await expect(page.getByTestId('policy-selected')).toBeChecked()
  await expect(page.getByTestId('policy-option-editor')).toBeChecked()

  const { context, page: editor } = await loggedOut(browser, sandboxUserAgent)

  try {
    await logIn(editor, email, password)
    await expect(editor).toHaveURL('/admin/login/two-factor/setup')
    await syncLV(editor)
    // No session before it is set up
    await editor.goto('/admin/users')
    await expect(editor).toHaveURL('/admin/login')

    await logIn(editor, email, password)
    await expect(editor).toHaveURL('/admin/login/two-factor/setup')
    await syncLV(editor)
    await editor.screenshot({ path: testInfo.outputPath('required-setup.png'), fullPage: true })

    const secret = (await editor.getByTestId('two-factor-secret').textContent()).trim()
    await editor.getByTestId('two-factor-setup-code').fill(totp(secret))
    await editor.getByTestId('two-factor-enable').click()
    await expect(editor.getByTestId('recovery-code')).toHaveCount(10)
    await editor.getByTestId('two-factor-continue').click()
    // On to where they were going
    await expect(editor).toHaveURL('/admin/users')
  } finally {
    await context.close()
  }
})

test('repeated wrong passwords lock the account for a while', async ({ browser, sandboxUserAgent }) => {
  const { email, password } = await fixture(sandboxUserAgent, 'user')
  const { context, page } = await loggedOut(browser, sandboxUserAgent)
  const alert = page.locator('#login_form .alert.danger')

  try {
    await logIn(page, email, 'wrong password')
    await expect(alert).toBeVisible()
    const invalid = await alert.textContent()

    for (let attempt = 2; attempt <= 4; attempt++) {
      await logIn(page, email, 'wrong password')
      await expect(alert).toHaveText(invalid)
    }

    // The fifth locks it
    await logIn(page, email, 'wrong password')
    await expect(alert).not.toHaveText(invalid)
    const locked = await alert.textContent()

    // Locked: the right password does not get in either, and the answer is the same
    await logIn(page, email, password)
    await expect(page).toHaveURL('/admin/login')
    await expect(alert).toHaveText(locked)
  } finally {
    await context.close()
  }
})

test('a superuser resets two-factor authentication for a user who lost their phone', async ({ page, browser, sandboxUserAgent }) => {
  const { email, password } = await fixture(sandboxUserAgent, 'enabled-user')

  await page.goto('/admin/users')
  await syncLV(page)
  await page.locator('.content-list .list-row').filter({ hasText: email }).getByRole('link', { name: 'Two-factor Editor' }).click()
  await syncLV(page)
  await expect(page.getByTestId('user-two-factor-status')).toBeVisible()

  await page.getByTestId('reset-two-factor').click()
  const dialog = page.getByRole('dialog')
  await dialog.getByRole('button', { name: 'Turn it off' }).click()
  await syncLV(page)
  await expect(page.getByTestId('reset-two-factor')).toHaveCount(0)

  const { context, page: user } = await loggedOut(browser, sandboxUserAgent)

  try {
    await logIn(user, email, password)
    await expect(user).toHaveURL('/admin')
  } finally {
    await context.close()
  }
})
