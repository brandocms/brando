import crypto from 'node:crypto'
import { test, expect } from '../../test-support/setupAuth'
import { e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// The E2E server's own receiver (`E2EWebhookReceiverController`) keeps every
// delivery with its headers and raw body. Webhooks may call it because the
// E2E config allows http on localhost.
const receiver = (inbox) => {
  const url = e2eUrl(`/e2e/webhook-receiver/${inbox}`)
  return {
    url,
    requests: async () => (await (await fetch(url)).json()).requests,
  }
}

// What a receiver does: HMAC-SHA256 of `t + "." + body` with the secret.
const verify = (request, secret) => {
  const parts = Object.fromEntries(request.headers['brando-signature'].split(',').map((p) => p.split('=')))
  const expected = crypto.createHmac('sha256', secret).update(`${parts.t}.${request.body}`).digest('hex')
  return expected === parts.v1 && Math.abs(Date.now() / 1000 - Number(parts.t)) < 300
}

const events = (requests) => requests.map((r) => r.headers['brando-event'])

test.describe('Webhooks', () => {
  test.setTimeout(120000)

  test('create, see the secret once, deliver on publish, redeliver and send a test event', async ({
    page,
    sandboxUserAgent,
  }, testInfo) => {
    const inbox = receiver(`inbox-${Date.now()}-${Math.round(Math.random() * 1e6)}`)
    await page.setViewportSize({ width: 1440, height: 900 })

    // Configuration → Integrations → Webhooks (Manage) → Add webhook
    await page.goto('/admin/config/integrations')
    await syncLV(page)
    await page.getByTestId('integration-webhooks').locator('a[href="/admin/config/webhooks"]').click()
    await expect(page).toHaveURL('/admin/config/webhooks')
    await syncLV(page)
    await page.getByTestId('webhook-new').click()
    await expect(page).toHaveURL('/admin/config/webhooks/new')
    await syncLV(page)

    await page.locator('#webhook-name').fill('E2E receiver')
    await page.locator('#webhook-url').fill(inbox.url)
    await page.getByTestId('webhook-save').click()
    await expect(page).toHaveURL(/\/admin\/config\/webhooks\/\d+\/edit$/)
    const webhookId = page.url().match(/webhooks\/(\d+)\/edit/)[1]

    // The secret, once
    const secretField = page.getByTestId('webhook-secret-value')
    await expect(page.getByTestId('webhook-secret')).toBeVisible()
    await expect(secretField).toHaveValue(/^whsec_/)
    await expect(secretField).toBeInViewport()
    await expect(secretField).toBeFocused()
    const secret = await secretField.inputValue()
    await page.screenshot({ path: testInfo.outputPath('webhook-secret.png') })

    await page.getByTestId('webhook-secret-done').click()
    await expect(page.getByTestId('webhook-secret')).toBeHidden()
    await expect(secretField).toHaveValue('')
    expect(await page.content()).not.toContain(secret)

    await page.reload()
    await syncLV(page)
    await expect(page.getByTestId('webhook-secret')).toBeHidden()
    expect(await page.content()).not.toContain(secret)

    // Publish a new page: entry.created, then entry.published
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Webhook launch')
    await page.getByLabel('URI').fill(`webhook-launch-${Date.now()}`)
    await page.getByTestId('status-trigger').click()
    await page.getByTestId('status-options').locator('label:has(input[value="published"])').click()
    await expect(page.getByTestId('status-options').locator('input[value="published"]')).toBeChecked()
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })

    await expect.poll(async () => events(await inbox.requests())).toEqual(['entry.created', 'entry.published'])
    const delivered = await inbox.requests()

    for (const request of delivered) {
      expect(verify(request, secret)).toBe(true)
      const payload = JSON.parse(request.body)
      expect(payload.delivery_id).toBe(request.headers['brando-delivery'])
      expect(payload.entry.type).toBe('pages.page')
      expect(payload.entry.status).toBe('published')
      expect(payload.actor).toEqual({ kind: 'person' })
      // No content, no person
      expect(request.body).not.toContain('Webhook launch')
      expect(request.body).not.toContain('admin@brandocms.com')
    }

    // The delivery log
    await page.goto(`/admin/config/webhooks/${webhookId}/deliveries`)
    await syncLV(page)
    const rows = page.getByTestId('webhook-log').locator('tbody tr')
    await expect(rows).toHaveCount(2)
    await expect(rows.first()).toHaveAttribute('data-state', 'succeeded')
    await expect(rows.first().getByTestId('delivery-state')).toContainText('200')
    await page.screenshot({ path: testInfo.outputPath('delivery-log.png'), fullPage: true })

    // On a phone the log stacks instead of widening the page. Polled: right
    // after the resize the layout can still be the desktop one (it read 112px
    // over once), which is the resize settling, not the log overflowing.
    await page.setViewportSize({ width: 390, height: 844 })
    await expect
      .poll(() => page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth))
      .toBeLessThanOrEqual(1)
    await page.setViewportSize({ width: 1440, height: 900 })

    // Redeliver: the same event, a new delivery id
    await rows.last().getByTestId('webhook-redeliver').click()
    await expect(rows).toHaveCount(3)
    await expect.poll(async () => (await inbox.requests()).length).toBe(3)
    const [original, , again] = await inbox.requests()
    const first = JSON.parse(original.body)
    const redelivered = JSON.parse(again.body)
    expect(redelivered.event_id).toBe(first.event_id)
    expect(redelivered.delivery_id).not.toBe(first.delivery_id)
    expect(verify(again, secret)).toBe(true)

    // Send a test event from a session that has not confirmed lately: the
    // password first
    const stale = await fetch(e2eUrl('/e2e/two-factor/stale-sessions'), {
      method: 'POST',
      headers: { 'user-agent': sandboxUserAgent, 'content-type': 'application/json' },
      body: JSON.stringify({ email: 'admin@brandocms.com' }),
    })
    expect(stale.ok).toBe(true)

    await page.getByTestId('webhook-send-test').click()
    const prompt = page.locator('#reauth-modal')
    await expect(prompt).toBeVisible()
    await prompt.getByTestId('reauth-proof').fill('brandocms')
    await prompt.getByTestId('reauth-submit').click()
    await expect(page.locator('#reauth-modal')).toHaveCount(0)

    await expect.poll(async () => events(await inbox.requests())).toContain('webhook.test')
    await expect(rows).toHaveCount(4)
    await expect(rows.first()).toHaveAttribute('data-state', 'succeeded')

    // Integrations shows the webhook and its last delivery
    await page.goto('/admin/config/integrations')
    await syncLV(page)
    await expect(page.getByTestId('integration-webhooks-status')).toBeVisible()
  })

  test('the screens fit a phone', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 })

    for (const path of ['/admin/config/integrations', '/admin/config/webhooks', '/admin/config/webhooks/new', '/admin/config/webhooks/deliveries']) {
      await page.goto(path)
      await syncLV(page)
      await expect(page.locator('.integrations-workspace')).toBeVisible()
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
      expect(overflow, path).toBeLessThanOrEqual(1)
    }
  })
})
