import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// A published project with a Mux cover video and the admin user as its author:
// the page's JSON-LD has an Article, a Person and a VideoObject.
async function seedProject(page, slug) {
  const video = await factory(page, 'Brando.Videos.Video', {
    type: 'mux', title: 'Walkthrough', status: 'ready', duration: '00:01:30', width: 1920, height: 1080,
    meta: { mux: { playback_id: 'structured-data-playback' } },
  })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Structured', slug: `client-${slug}`, status: 'published', language: 'en' })
  return factory(page, 'E2eProject.Projects.Project', {
    title: 'Structured project', slug, client_id: client.id, status: 'published', language: 'en',
    introduction: '<p>Intro</p>', cover_video_id: video.id,
  })
}

const node = (inspector, type) => inspector.locator(`[data-testid="structured-data-node-${type}"]`)

// Structural locators only: labels are translated and must not be pinned.
test('the structured data inspector shows the graph the page emits', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const project = await seedProject(page, 'structured-project')

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  await page.locator('button.form-tool-meta').click()
  const drawer = page.locator('.drawer.editor-workspace-drawer').filter({ has: page.locator('[data-testid="meta-tab-structured-data"]') })
  const tab = drawer.locator('[data-testid="meta-tab-structured-data"]')
  await tab.click()
  await syncLV(page)
  await expect(tab).toHaveAttribute('aria-pressed', 'true')
  await expect(drawer).toHaveClass(/structured-data-open/)

  const inspector = drawer.locator('.structured-data')
  for (const type of ['WebSite', 'Organization', 'WebPage', 'Article', 'Person', 'VideoObject']) {
    await expect(node(inspector, type)).toBeVisible()
  }

  // The article is selected first; the video lacks a description (a warning);
  // no image is mapped, so the image is a dashed node.
  await expect(node(inspector, 'Article')).toHaveAttribute('aria-pressed', 'true')
  await expect(node(inspector, 'VideoObject')).toHaveAttribute('data-level', 'warning')
  await expect(node(inspector, 'ImageObject')).toHaveAttribute('data-potential', 'true')
  await expect(inspector.locator('.structured-data-edges text', { hasText: 'author' })).toHaveCount(1)
  await expect(inspector.locator('.structured-data-edges text', { hasText: 'video' })).toHaveCount(1)

  const mapping = inspector.locator('.structured-data-mapping')
  await expect(mapping.locator('h3')).toHaveText('Article')
  const author = mapping.locator('.structured-data-rows li', { has: page.locator('code', { hasText: /^author$/ }) })
  await expect(author.locator('.structured-data-source')).toHaveText('creator')
  const image = mapping.locator('.structured-data-rows li', { has: page.locator('code', { hasText: /^image$/ }) })
  await expect(image).toHaveAttribute('data-status', 'warning')
  await expect(image.locator('.structured-data-source')).toHaveAttribute('data-mapped', 'false')

  await page.screenshot({ path: testInfo.outputPath('structured-data-desktop.png'), animations: 'disabled' })

  // Selecting a node shows its mapping
  await node(inspector, 'VideoObject').click()
  await syncLV(page)
  await expect(node(inspector, 'VideoObject')).toHaveAttribute('aria-pressed', 'true')
  await expect(node(inspector, 'Article')).toHaveAttribute('aria-pressed', 'false')
  await expect(mapping.locator('h3')).toHaveText('VideoObject')
  await expect(mapping.locator('.structured-data-rows li[data-status="warning"] code')).toHaveText('description')

  await node(inspector, 'Person').focus()
  await page.keyboard.press('Enter')
  await syncLV(page)
  await expect(node(inspector, 'Person')).toHaveAttribute('aria-pressed', 'true')
  await expect(mapping.locator('h3')).toHaveText('Person')

  // Copy JSON-LD gives the exact content of the page's script tag.
  await page.context().grantPermissions(['clipboard-read', 'clipboard-write'], { origin: new URL(page.url()).origin })
  await mapping.locator('[data-copy-json-ld]').click()
  await expect(mapping.locator('[data-copy-json-ld]')).toHaveAttribute('data-copied', 'true')
  const copied = await page.evaluate(() => navigator.clipboard.readText())

  const html = await (await page.request.get('/project/structured-project')).text()
  const script = html.match(/<script type="application\/ld\+json">([\s\S]*?)<\/script>/)[1].trim()
  expect(copied).toBe(script)

  const graph = JSON.parse(copied)['@graph']
  expect(graph.find(entity => entity['@type'] === 'VideoObject').name).toBe('Walkthrough')
  expect(graph.find(entity => entity['@type'] === 'Person')['@id']).toContain('#/schema/person/')

  // A published entry with a page can be sent to Google's Rich Results Test.
  const rich = mapping.locator('a[data-rich-results]')
  await expect(rich).toHaveAttribute('target', '_blank')
  const pageUrl = new URL('/project/structured-project', page.url()).toString()
  await expect(rich).toHaveAttribute('href', `https://search.google.com/test/rich-results?url=${encodeURIComponent(pageUrl)}`)

  // The meta fields are one tab away, with their input intact.
  await drawer.locator('.meta-drawer-tabs button').first().click()
  await expect(drawer.locator('textarea[name$="[meta_description]"]')).toBeVisible()
  await expect(inspector).toBeHidden()

  await page.setViewportSize({ width: 390, height: 844 })
  await tab.click()
  await syncLV(page)
  await expect(node(inspector, 'Article')).toBeVisible()
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
  await page.screenshot({ path: testInfo.outputPath('structured-data-mobile.png'), animations: 'disabled' })
})

test('an unpublished entry cannot be sent to the Rich Results Test', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Draft client', slug: 'draft-client', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Draft project', slug: 'draft-structured', client_id: client.id, status: 'draft', language: 'en', introduction: '<p>Intro</p>',
  })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await page.locator('button.form-tool-meta').click()
  await page.locator('[data-testid="meta-tab-structured-data"]').click()
  await syncLV(page)

  const rich = page.locator('.structured-data-mapping [data-rich-results]')
  await expect(rich).toBeDisabled()
  await expect(page.locator('.structured-data-disabled-reason')).toBeVisible()
  await expect(rich).toHaveAttribute('aria-describedby', /rich-results-reason/)
})

test('Content SEO counts entries with structured data issues and opens them in the inspector', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const project = await seedProject(page, 'structured-seo-project')

  await page.goto('/admin/config/seo?tab=content')
  await syncLV(page)

  // The check is cached for a while; run it again for this test's entries.
  const section = page.locator('#seo-structured-data')
  await expect(section.locator('.seo-stats')).toBeVisible({ timeout: 15000 })
  await page.locator('.seo-audit button[phx-click="rerun_audit"]').click()
  await syncLV(page)
  await expect(section.locator('.seo-stats')).toBeVisible({ timeout: 15000 })

  await expect(section.locator('[data-testid="structured-data-warnings"] dd')).not.toHaveText('0')
  const row = section.locator('tr.seo-structured-data-row', { hasText: 'Structured project' })
  await expect(row).toHaveCount(1)
  await expect(row.locator('td.seo-number').nth(1)).not.toHaveText('0')

  const link = row.locator('a.seo-row-action')
  await expect(link).toHaveAttribute('href', `/admin/projects/projects/update/${project.id}#structured-data`)
  await link.click()
  await page.waitForURL(new RegExp(`/admin/projects/projects/update/${project.id}`))
  await syncLV(page)

  // Opened on the Structured data tab, with the hash dropped.
  const tab = page.locator('[data-testid="meta-tab-structured-data"]')
  await expect(tab).toHaveAttribute('aria-pressed', 'true')
  await expect(node(page.locator('.structured-data'), 'Article')).toBeVisible()
  await expect.poll(() => new URL(page.url()).hash).toBe('')
})
