import { test, expect } from '../../test-support/setupAuth'
import { baseURL, e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// A lowered role reaches a page that is already open: its view ends, the client
// rejoins, and the view mounts at the stored role with the form recovering
// what was typed. LiveViewTest has no transport, so this needs a browser.
// With groups, a role decides nothing.
test.skip(process.env.BRANDO_AUTHORIZATION_MODE === 'groups', 'Legacy roles')

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

const signedIn = async (browser, userAgent, role) => {
  const user = await fixture(userAgent, 'user')
  await fixture(userAgent, 'set-role', { id: user.id, role })
  const context = await browser.newContext({ baseURL, userAgent })
  const page = await context.newPage()
  await logIn(page, user.email, user.password)
  return { user, context, page }
}

// The first of Phoenix's `rejoinAfterMs`, which the admin's LiveSocket leaves as it is
const CHANNEL_REJOIN_MS = 1000

// A rejoin opens no new websocket: it is a join sent on the one that stays.
const countJoins = (page) => {
  const joins = { count: 0 }
  page.on('websocket', (socket) => {
    socket.on('framesent', ({ payload }) => {
      if (String(payload).includes('"phx_join"') && String(payload).includes('"lv:phx-')) joins.count += 1
    })
  })
  return joins
}

test('an entry form stays, with what was typed, when an administrator becomes an editor', async ({ browser, sandboxUserAgent }) => {
  const { user, context, page } = await signedIn(browser, sandboxUserAgent, 'admin')

  try {
    const joins = countJoins(page)

    await page.goto('/admin/pages/update/1')
    await syncLV(page)
    const title = page.getByLabel('Title', { exact: true })
    await title.fill('Typed before the demotion')
    await syncLV(page)
    const joinsBefore = joins.count
    // Gone if the page reloads, which would lose what was typed
    await page.evaluate(() => { window.staleAuthorityMarker = true })

    await fixture(sandboxUserAgent, 'set-role', { id: user.id, role: 'editor' })
    await expect.poll(() => joins.count).toBeGreaterThan(joinsBefore)
    await syncLV(page)

    expect(await page.evaluate(() => window.staleAuthorityMarker)).toBe(true)
    await expect(page).toHaveURL('/admin/pages/update/1')
    await expect(title).toHaveValue('Typed before the demotion')
  } finally {
    await context.close()
  }
})

test('a superuser screen leaves when its superuser is demoted', async ({ browser, sandboxUserAgent }) => {
  const { user, context, page } = await signedIn(browser, sandboxUserAgent, 'superuser')

  try {
    await page.goto('/admin/users/sign-in-policy')
    await syncLV(page)
    await expect(page.locator('#sign-in-policy-form')).toBeVisible()

    await fixture(sandboxUserAgent, 'set-role', { id: user.id, role: 'editor' })

    await expect(page).toHaveURL('/admin/users', { timeout: 15000 })
  } finally {
    await context.close()
  }
})

test('saving someone else leaves an open form as it is', async ({ browser, sandboxUserAgent }) => {
  const { context, page } = await signedIn(browser, sandboxUserAgent, 'editor')
  const other = await fixture(sandboxUserAgent, 'user')

  try {
    const joins = countJoins(page)

    await page.goto('/admin/pages/update/1')
    await syncLV(page)
    const title = page.getByLabel('Title', { exact: true })
    await title.fill('Typed by an editor')
    await syncLV(page)
    const joinsBefore = joins.count

    await fixture(sandboxUserAgent, 'set-role', { id: other.id, role: 'admin' })
    // Nothing to wait on when nothing happens: a view ended by mistake would rejoin
    // when the channel's rejoin timer fires, so watch past it.
    await page.waitForTimeout(CHANNEL_REJOIN_MS + 500)
    await syncLV(page)

    expect(joins.count).toBe(joinsBefore)
    await expect(title).toHaveValue('Typed by an editor')
  } finally {
    await context.close()
  }
})
