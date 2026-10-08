import { createHash, randomBytes } from 'node:crypto'
import { request as playwrightRequest } from '@playwright/test'
import { test, expect } from '../../test-support/setupAuth'
import { baseURL, e2eUrl } from '../../test-support/e2eUrl'
import { totp } from '../../test-support/totp'
import { syncLV } from '../../utils'

// The remote MCP endpoint (Brando.MCP), as an MCP client meets it: discovery,
// sign-in with two-factor authentication, the consent screen, the code
// exchange with PKCE, tool calls with the token, and the person disconnecting
// it under Security → Connected apps. The client's metadata document is
// served by the E2E app (E2eProject.MCPClient); its redirect URI is a
// loopback address that nothing listens on, so the test catches the
// browser's request to it.

const fixture = async (userAgent, action, body = {}) => {
  const response = await fetch(e2eUrl(`/e2e/mcp/${action}`), {
    method: 'POST',
    headers: { 'user-agent': userAgent, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  expect(response.ok).toBe(true)
  return response.json()
}

const base64url = (buffer) => buffer.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
const redirectUri = 'http://127.0.0.1:43123/callback'

const rpc = (api, endpoint, token, id, method, params = {}) =>
  api.post(endpoint, {
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      accept: 'application/json, text/event-stream',
      'mcp-protocol-version': '2025-06-18',
    },
    data: { jsonrpc: '2.0', id, method, params },
  })

test('a person connects an MCP client with two-factor sign-in, the client calls tools, and disconnecting stops it', async ({
  browser,
  sandboxUserAgent,
}) => {
  // In the person's own language: the screens are driven by test ids and roles.
  const { email, password, secret, client_id } = await fixture(sandboxUserAgent, 'user', { language: 'no' })
  const { resource } = await fixture(sandboxUserAgent, 'enable')
  const api = await playwrightRequest.newContext({ extraHTTPHeaders: { 'user-agent': sandboxUserAgent } })
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const page = await context.newPage()

  try {
    // Discovery: the endpoint says where to sign in.
    const challenge401 = await rpc(api, resource, 'bmcp_at_nothing', 1, 'tools/list')
    expect(challenge401.status()).toBe(401)
    expect(challenge401.headers()['www-authenticate']).toContain('resource_metadata=')

    const prm = await (await api.get(`${baseURL}/.well-known/oauth-protected-resource/mcp`)).json()
    expect(prm.resource).toBe(resource)
    const as = await (await api.get(`${baseURL}/.well-known/oauth-authorization-server/mcp`)).json()
    expect(as.code_challenge_methods_supported).toEqual(['S256'])
    expect(as.client_id_metadata_document_supported).toBe(true)

    const verifier = base64url(randomBytes(32))
    const challenge = base64url(createHash('sha256').update(verifier).digest())
    const authorize = new URL(as.authorization_endpoint)
    authorize.search = new URLSearchParams({
      response_type: 'code',
      client_id,
      redirect_uri: redirectUri,
      code_challenge: challenge,
      code_challenge_method: 'S256',
      state: 'e2e-state',
      scope: 'content',
      resource,
    }).toString()

    // Not signed in: the admin's login, with the second step, then back.
    await page.goto(authorize.toString())
    await expect(page).toHaveURL(/\/admin\/login/)
    await syncLV(page)
    await page.getByTestId('email').fill(email)
    await page.getByTestId('password').fill(password)
    await page.getByTestId('login-button').click()
    await expect(page).toHaveURL('/admin/login/two-factor')
    await syncLV(page)
    await page.getByTestId('two-factor-code').fill(totp(secret))
    await page.getByTestId('two-factor-submit').click()

    // The consent screen names the client and the site; nothing happens without Allow.
    const consent = page.getByTestId('mcp-consent')
    await expect(consent).toHaveAttribute('data-state', 'consent')
    await syncLV(page)
    await expect(page.getByTestId('mcp-consent-client')).toHaveText('E2E Assistant')
    await expect(page.getByTestId('mcp-consent-site')).not.toBeEmpty()
    await expect(page.locator('html')).toHaveAttribute('lang', 'no')

    const callback = page.waitForRequest((r) => r.url().startsWith(redirectUri))
    await page.route(`${redirectUri}**`, (route) => route.fulfill({ status: 200, body: 'ok' }))
    await page.getByTestId('mcp-consent-approve').click()
    const returned = new URL((await callback).url())
    expect(returned.searchParams.get('state')).toBe('e2e-state')
    expect(returned.searchParams.get('iss')).toBe(resource)
    const code = returned.searchParams.get('code')
    expect(code).toMatch(/^bmcp_ac_/)

    // The client exchanges the code with its verifier.
    const tokenResponse = await api.post(as.token_endpoint, {
      form: {
        grant_type: 'authorization_code',
        code,
        code_verifier: verifier,
        client_id,
        redirect_uri: redirectUri,
        resource,
      },
    })
    expect(tokenResponse.status()).toBe(200)
    const tokens = await tokenResponse.json()
    expect(tokens.token_type).toBe('Bearer')

    // tools/list and tools/call with the token
    const list = await (await rpc(api, resource, tokens.access_token, 2, 'tools/list')).json()
    const names = list.result.tools.map((tool) => tool.name)
    expect(names).toContain('brando_content_list_content_types')
    expect(names).toContain('brando_content_prepare_proposal')
    expect(names.some((name) => /apply|delete/.test(name))).toBe(false)

    const call = await (
      await rpc(api, resource, tokens.access_token, 3, 'tools/call', {
        name: 'brando_content_list_content_types',
        arguments: {},
      })
    ).json()
    expect(call.result.isError).toBeFalsy()
    expect(call.result.structuredContent.content_types.length).toBeGreaterThan(0)

    // The connection under Security → Connected apps, where the person disconnects it.
    await page.goto('/admin/users/security')
    await syncLV(page)
    const app = page.getByTestId('connected-app')
    await expect(app).toHaveCount(1)
    await expect(app).toContainText('E2E Assistant')
    await app.getByTestId('connected-app-revoke').click()
    await page.locator('dialog.admin-dialog .admin-dialog-button.is-danger').click()
    await expect(page.getByTestId('connected-app')).toHaveCount(0)

    // The next call is refused, and so is the refresh token.
    const after = await rpc(api, resource, tokens.access_token, 4, 'tools/list')
    expect(after.status()).toBe(401)
    const refresh = await api.post(as.token_endpoint, {
      form: { grant_type: 'refresh_token', refresh_token: tokens.refresh_token, client_id },
    })
    expect(refresh.status()).toBe(400)

    // A code works once.
    const replay = await api.post(as.token_endpoint, {
      form: { grant_type: 'authorization_code', code, code_verifier: verifier, client_id, redirect_uri: redirectUri },
    })
    expect(replay.status()).toBe(400)
  } finally {
    await api.dispose()
    await context.close()
  }
})

test('the endpoint answers as missing until it is turned on', async ({ sandboxUserAgent }) => {
  const api = await playwrightRequest.newContext({ extraHTTPHeaders: { 'user-agent': sandboxUserAgent } })

  try {
    for (const path of ['/.well-known/oauth-protected-resource/mcp', '/.well-known/oauth-authorization-server/mcp']) {
      expect((await api.get(`${baseURL}${path}`)).status()).toBe(404)
    }
    expect((await api.post(`${baseURL}/mcp`, { data: { jsonrpc: '2.0', id: 1, method: 'ping' } })).status()).toBe(404)
    expect((await api.post(`${baseURL}/mcp/oauth/token`, { form: { grant_type: 'refresh_token' } })).status()).toBe(404)
  } finally {
    await api.dispose()
  }
})
