import { test, expect } from '../../test-support/setupAuth'
import { e2eUrl } from '../../test-support/e2eUrl'
import { syncLV } from '../../utils'

// The E2E server's own receiver (`E2EWebhookReceiverController`) keeps every
// request with its headers and raw body. A Slack route may post to it because
// the E2E config allows http on localhost, as for webhooks.
const receiver = (inbox) => {
  const url = e2eUrl(`/e2e/webhook-receiver/${inbox}`)
  return {
    url,
    requests: async () => (await (await fetch(url)).json()).requests,
  }
}

test.describe('Notifications', () => {
  test.setTimeout(120000)

  test.beforeEach(async ({ page }) => {
    const response = await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
    expect(response.ok()).toBe(true)
  })

  test('create a Slack route, keep its URL hidden and send a test message', async ({ page }, testInfo) => {
    const inbox = `notify-${Date.now()}-${Math.round(Math.random() * 1e6)}`
    const slack = receiver(inbox)
    await page.setViewportSize({ width: 1440, height: 900 })

    // Configuration → Integrations → Notifications (Set up)
    await page.goto('/admin/config/integrations')
    await syncLV(page)
    await expect(page.locator('html')).toHaveAttribute('lang', 'no')
    const row = page.getByTestId('integration-notifications')
    await expect(row.getByRole('heading', { name: 'Varsler' })).toBeVisible()
    await row.getByRole('link', { name: 'Sett opp' }).click()
    await expect(page).toHaveURL('/admin/config/notifications/new')
    await syncLV(page)

    const form = page.getByTestId('notification-route-form')
    await form.getByLabel('Navn', { exact: true }).fill('Redaksjonen')
    await expect(form.getByRole('radio', { name: 'Slack' })).toBeChecked()
    await form.getByLabel('Webhook-URL', { exact: true }).fill(slack.url)
    await form.getByRole('checkbox', { name: /Publisert som planlagt/ }).check()
    await form.getByRole('checkbox', { name: /Feilede jobber/ }).check()
    await page.screenshot({ path: testInfo.outputPath('notification-route-new.png'), fullPage: true })
    await form.getByRole('button', { name: 'Opprett rute' }).click()

    await expect(page).toHaveURL(/\/admin\/config\/notifications\/\d+\/edit$/)
    const routeId = page.url().match(/notifications\/(\d+)\/edit/)[1]
    await syncLV(page)

    // Saved, the URL shows only by host and last characters, after a reload too
    await expect(page.getByTestId('notification-url-masked')).toHaveText(new RegExp(`…${inbox.slice(-4)}$`))
    expect(await page.content()).not.toContain(inbox)
    await page.reload()
    await syncLV(page)
    expect(await page.content()).not.toContain(inbox)
    await expect(page.getByTestId('notification-route-state')).toHaveText('Aktiv')

    // A test message: Slack blocks with a link back to the admin
    await page.getByRole('button', { name: 'Send test' }).click()
    await expect.poll(async () => (await slack.requests()).length).toBe(1)
    const [request] = await slack.requests()
    expect(request.headers['content-type']).toBe('application/json')
    const body = JSON.parse(request.body)
    expect(body.text).toContain('Testvarsel')
    expect(body.blocks[0].type).toBe('section')
    expect(body.blocks[0].text.text).toContain(`/admin/config/notifications/${routeId}/deliveries`)

    // The delivery log
    await page.goto(`/admin/config/notifications/${routeId}/deliveries`)
    await syncLV(page)
    const rows = page.getByTestId('notification-log').locator('tbody tr')
    await expect(rows).toHaveCount(1)
    await expect(rows.first()).toHaveAttribute('data-state', 'succeeded')
    await page.screenshot({ path: testInfo.outputPath('notification-log.png'), fullPage: true })

    // Listed, and counted on Integrations
    await page.goto('/admin/config/notifications')
    await syncLV(page)
    await expect(page.getByTestId('notification-route-list').getByRole('heading', { name: /Redaksjonen/ })).toBeVisible()
    await page.goto('/admin/config/integrations')
    await syncLV(page)
    await expect(page.getByTestId('integration-notifications-status')).toBeVisible()
  })

  test('the screens fit a phone', async ({ page }) => {
    await page.setViewportSize({ width: 390, height: 844 })

    for (const path of [
      '/admin/config/notifications',
      '/admin/config/notifications/new',
      '/admin/config/notifications/deliveries',
    ]) {
      await page.goto(path)
      await syncLV(page)
      await expect(page.locator('.integrations-workspace')).toBeVisible()
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth - window.innerWidth)
      expect(overflow, path).toBeLessThanOrEqual(1)
    }
  })
})

test.describe('Notifications paused after failures', () => {
  test('the dashboard says so, links to the route, and the failed message can be sent again', async ({
    page,
  }) => {
    const fixture = await page.request.post('/e2e/setup_fixtures/notification-route-paused')
    expect(fixture.ok()).toBe(true)
    const norwegian = await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
    expect(norwegian.ok()).toBe(true)
    const slack = receiver('notification-route-paused')
    const before = (await slack.requests()).length
    await page.setViewportSize({ width: 1440, height: 900 })

    await page.goto('/admin')
    await syncLV(page)
    const notice = page.getByTestId('dashboard-notifications-paused')
    await expect(notice).toBeVisible()
    await expect(notice).toContainText("Editors' channel")
    await notice.getByRole('link', { name: 'Gå gjennom varsler' }).click()
    await expect(page).toHaveURL(/\/admin\/config\/notifications\/\d+\/edit$/)
    await syncLV(page)
    await expect(page.getByTestId('notification-route-state')).toHaveText('På pause etter feil')

    // Resume, then send the failed message again from the log
    await page.getByRole('button', { name: 'Gjenoppta' }).click()
    await expect(page.getByTestId('notification-route-state')).toHaveText('Aktiv')
    await page.getByRole('link', { name: 'Leveringslogg' }).click()
    await syncLV(page)
    const rows = page.getByTestId('notification-log').locator('tbody tr')
    await expect(rows).toHaveCount(1)
    await rows.first().getByRole('button', { name: 'Lever på nytt' }).click()
    await expect(rows).toHaveCount(2)
    await expect(rows.first()).toHaveAttribute('data-state', 'succeeded')
    await expect.poll(async () => (await slack.requests()).length).toBe(before + 1)
    const body = JSON.parse((await slack.requests()).at(-1).body)
    expect(body.text).toContain('E2eProject.Worker.Sync')

    await page.goto('/admin')
    await syncLV(page)
    await expect(page.getByTestId('dashboard-notifications-paused')).toHaveCount(0)
  })
})
