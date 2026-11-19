import { request as playwrightRequest } from '@playwright/test'
import { test, expect } from '../../test-support/setupAuth'
import { e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// The live page of a connected tool (Brando.MCP.Watch): a person's
// connection (made by the fixture through the consent screen's functions)
// calls tools over the endpoint, and the admin, who manages connected
// tools, follows each call on the page as it happens.

const fixture = async (userAgent, action, body = {}) => {
  const response = await fetch(e2eUrl(`/e2e/mcp/${action}`), {
    method: 'POST',
    headers: { 'user-agent': userAgent, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  })
  expect(response.ok).toBe(true)
  return response.json()
}

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

const tool = async (api, resource, token, id, name, args = {}) =>
  (await (await rpc(api, resource, token, id, 'tools/call', { name, arguments: args })).json()).result

test('follows a connected tool’s calls as they happen', async ({ page, sandboxUserAgent }, testInfo) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const { email } = await fixture(sandboxUserAgent, 'user')
  const { resource } = await fixture(sandboxUserAgent, 'enable')
  const {
    access_token: token,
    watch_path: watchPath,
    page_id: pageId,
  } = await fixture(sandboxUserAgent, 'connect', { email })
  const api = await playwrightRequest.newContext({ extraHTTPHeaders: { 'user-agent': sandboxUserAgent } })

  try {
    // The server's instructions end with the page's link
    const init = await (await rpc(api, resource, token, 1, 'initialize', { protocolVersion: '2025-06-18' })).json()
    expect(init.result.instructions).toContain(watchPath)

    await page.goto(watchPath)
    await syncLV(page)
    const watch = page.getByTestId('mcp-watch')
    await expect(watch).toHaveAttribute('data-live', 'true')
    await expect(page.getByTestId('mcp-watch-status')).toBeVisible()
    await expect(page.getByTestId('mcp-watch-empty')).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('mcp-watch-empty.png') })

    // The first result carries the link, for clients that hide the instructions
    const first = await tool(api, resource, token, 2, 'brando_content_list_content_types')
    expect(first.structuredContent.watch_url).toContain(watchPath)

    const calls = watch.locator('.mcp-watch-call')
    await expect(calls).toHaveCount(1)
    await expect(page.getByTestId('mcp-watch-empty')).toHaveCount(0)
    await expect(calls.first()).toHaveAttribute('data-state', 'ok')
    await expect(calls.first()).toHaveAttribute('data-tool', 'list_content_types')

    await tool(api, resource, token, 3, 'brando_content_search_entries', {
      content_type: 'Brando.Pages.Page',
      query: 'MCP live',
    })
    await expect(watch.locator('.mcp-watch-call[data-tool="search_entries"] .assistant-step-term')).toHaveText('“MCP live”')

    // A failed call: its error is under it
    await tool(api, resource, token, 4, 'brando_content_describe_module', { module: 'local:0' })
    const failed = watch.locator('.mcp-watch-call[data-tool="describe_module"]')
    await expect(failed).toHaveAttribute('data-state', 'error')
    await expect(failed.locator('.mcp-watch-error')).toBeVisible()

    // An import, as the Figma tool tells it: the thumbnails, new and reused
    await fixture(sandboxUserAgent, 'watch-import', { watch_path: watchPath })
    const imported = watch.locator('#mcp-call-e2e-import')
    await expect(imported.locator('.mcp-watch-folder')).toContainText('Figma/Case – Tipping')
    await expect(imported.locator('li[data-reused="true"]')).toHaveCount(1)
    await expect(imported.locator('li[data-reused="false"]').first()).toBeVisible()

    // A proposal, with its link to the review, also in the result
    const proposal = await tool(api, resource, token, 5, 'brando_content_prepare_proposal', {
      summary: 'Retitle from the live page spec',
      operations: [
        {
          op: 'set_fields',
          target: { content_type: 'Brando.Pages.Page', id: pageId },
          fields: { title: 'Retitled over MCP' },
        },
      ],
    })
    expect(proposal.structuredContent.watch_url).toContain(watchPath)
    const card = watch.locator(`[data-proposal-id="${proposal.structuredContent.proposal_id}"]`)
    await expect(card.locator('h3')).toHaveText('Retitle from the live page spec')
    await expect(card.locator(`a[href="/admin/assistant/connected/${proposal.structuredContent.proposal_id}"]`)).toBeVisible()

    await expect(calls).toHaveCount(5)
    await expect(calls.first()).toHaveAttribute('data-tool', 'prepare_proposal')
    await page.screenshot({ path: testInfo.outputPath('mcp-watch-calls.png'), fullPage: true })

    // Opened again, it starts from Activity: every call but the fixture's import
    await page.reload()
    await syncLV(page)
    await expect(calls).toHaveCount(4)
    await expect(card.locator('h3')).toHaveText('Retitle from the live page spec')

    await page.setViewportSize({ width: 390, height: 900 })
    await expect(calls.first()).toBeVisible()
    await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(0)
    await page.screenshot({ path: testInfo.outputPath('mcp-watch-mobile.png'), fullPage: true })
  } finally {
    await api.dispose()
  }
  expect(errors).toEqual([])
})
