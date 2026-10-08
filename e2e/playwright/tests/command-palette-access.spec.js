import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import { e2eUrl } from '../test-support/e2eUrl'

// The command palette lists only what the user may open (group authorization).
test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups', 'Requires explicit group mode')

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test("a user without access to a content type doesn't see its entries or its create action", async ({
  page,
  secondUserPage,
  sandboxUserAgent,
}) => {
  const lighthousePage = await factory(page, 'Brando.Pages.Page', {
    title: 'Lighthouse page', uri: 'lighthouse', language: 'en', status: 'published',
  })
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Palette owner', slug: 'palette-owner', status: 'published', language: 'en',
  })
  await factory(page, 'E2eProject.Projects.Project', {
    title: 'Lighthouse case', slug: 'lighthouse-case', client_id: client.id, introduction: '<p>Intro</p>',
    status: 'published', language: 'en',
  })

  // The admin finds both
  await page.goto('/admin')
  await syncLV(page)
  await page.keyboard.press('ControlOrMeta+k')
  await page.locator('#command-palette-input').fill('lighthouse')
  await expect(page.locator('#command-palette-results')).toHaveAttribute('data-query', 'lighthouse')
  await expect(page.locator('#command-palette-group-entries [role=option].is-entry')).toHaveCount(2)

  // The editor may read, create and edit pages, and nothing about projects
  const response = await fetch(e2eUrl('/e2e/authorization/author'), {
    method: 'POST',
    headers: { 'user-agent': sandboxUserAgent },
  })
  expect(response.ok).toBe(true)

  await secondUserPage.setViewportSize({ width: 1440, height: 900 })
  await secondUserPage.goto('/admin')
  await syncLV(secondUserPage)
  await secondUserPage.keyboard.press('ControlOrMeta+k')
  const input = secondUserPage.locator('#command-palette-input')
  const results = secondUserPage.locator('#command-palette-results')
  await expect(input).toBeFocused()

  await input.fill('lighthouse')
  await expect(results).toHaveAttribute('data-query', 'lighthouse')
  const entries = secondUserPage.locator('#command-palette-group-entries [role=option].is-entry')
  await expect(entries).toHaveCount(1)
  await expect(entries.first()).toHaveAttribute('href', `/admin/pages/update/${lighthousePage.id}`)
  await expect(results.locator('a[href^="/admin/projects/"]')).toHaveCount(0)

  await input.fill('>')
  await expect(results).toHaveAttribute('data-query', '>')
  await expect(results.locator('a[href="/admin/pages/create"]')).toHaveCount(1)
  await expect(results.locator('a[href="/admin/projects/projects/create"]')).toHaveCount(0)
})
