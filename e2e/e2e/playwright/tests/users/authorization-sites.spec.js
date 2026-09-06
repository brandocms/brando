import { test, expect } from '../../test-support/setupAuth'
import { syncLV, toggleLivePreview } from '../../utils'
import { e2eUrl } from '../../test-support/e2eUrl'

test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups' || !['multi', 'single'].includes(process.env.BRANDO_TENANCY_MODE), 'Requires tenant group mode')

async function fixture(userAgent, action, params = {}) {
  const response = await fetch(e2eUrl(`/e2e/authorization-sites/${action}`), {
    method: 'POST', headers: { 'user-agent': userAgent, 'content-type': 'application/json' }, body: JSON.stringify(params)
  })
  expect(response.ok, await response.clone().text()).toBe(true)
  return response.json()
}

async function switchTo(page, name, value) {
  // Navigation is a child LiveView and connects after the main page.
  await expect(page.locator('#brando-nav')).toHaveClass(/phx-connected/)
  const menu = page.locator('.tenant-switcher')
  if (await menu.getAttribute('open') === null) await menu.locator('summary').click()
  await expect(menu).toHaveAttribute('open', '')
  await menu.locator(`button[name="${name}"][value="${value}"]`).click()
  await syncLV(page)
}

test('isolates roles, membership, reads and writes across sites and environments', async ({ secondUserPage: editor, sandboxUserAgent }) => {
  const data = await fixture(sandboxUserAgent, 'setup')
  await editor.goto('/admin/groups')
  await syncLV(editor)
  await expect(editor.locator('.authorization-scope')).toContainText('Alpha')
  await expect(editor.locator(`[data-user-id="${data.outsider_id}"]`)).toHaveCount(0)
  await editor.goto('/admin/pages/update/1')
  await syncLV(editor)
  await expect(editor.getByLabel('Title', { exact: true })).toHaveValue('Alpha production page')
  await switchTo(editor, 'environment_key', 'staging')
  await expect(editor.getByLabel('Title', { exact: true })).toHaveValue('Alpha staging page')
  await editor.getByLabel('Title', { exact: true }).fill('Edited only in staging')
  await editor.getByTestId('submit').click()
  await syncLV(editor)
  await expect.poll(async () => (await fixture(sandboxUserAgent, 'titles'))['auth-alpha/staging'].title).toBe('Edited only in staging')
  const titles = await fixture(sandboxUserAgent, 'titles')
  expect(titles['auth-alpha/staging'].title).toBe('Edited only in staging')
  expect(titles['auth-alpha/production'].title).toBe('Alpha production page')
  expect(titles['auth-beta/production'].title).toBe('Beta production page')

  if (process.env.BRANDO_TENANCY_MODE === 'multi') {
    await editor.goto('/admin/pages')
    await syncLV(editor)
    await switchTo(editor, 'site_key', 'auth-beta')
    await expect(editor.locator('#list-row-1')).toContainText('Beta production page')
    await expect(editor.getByRole('link', { name: 'Create page', exact: true })).toHaveCount(0)
    await expect(editor.locator(`[data-user-id="${data.outsider_id}"]`)).toBeVisible()
    await editor.evaluate(() => window.liveSocket.main.channel.push('event', { type: 'click', event: 'delete_entry', value: { id: '1' } }))
    await syncLV(editor)
    await expect(editor.locator('#list-row-1')).toBeVisible()
    await editor.goto('/admin/pages/update/1')
    await expect(editor).toHaveURL('/admin/access-denied')
    await editor.goto('/admin/groups')
    await expect(editor).toHaveURL('/admin/access-denied')
  }
})

test('private previews reject other accounts and close after site access is revoked', async ({ page: owner, secondUserPage: editor, sandboxUserAgent }) => {
  const data = await fixture(sandboxUserAgent, 'setup')
  await editor.goto('/admin/pages/update/1')
  await syncLV(editor)
  // Use the real preview flow, including unsaved rendering and its socket.
  await toggleLivePreview(editor)
  const frame = editor.locator('iframe[src*="/__livepreview?"]')
  await expect(frame).toBeVisible()
  const previewURL = await frame.getAttribute('src')
  await expect(editor.frameLocator('iframe[src*="/__livepreview?"]').locator('main')).toBeVisible()
  const denied = await owner.request.get(previewURL)
  expect(denied.status()).toBe(403)
  const allowed = await editor.request.get(previewURL)
  expect(allowed.status()).toBe(200)
  await fixture(sandboxUserAgent, 'revoke', { group_id: data.alpha_group_id })
  await expect(editor).toHaveURL('/admin/access-denied')
  const revoked = await editor.request.get(previewURL)
  expect(revoked.status()).toBe(403)
})
