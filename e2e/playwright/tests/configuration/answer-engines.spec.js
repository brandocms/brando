import { test, expect } from '../../test-support/setupAuth'
import { syncLV, setEntryStatus } from '../../utils'

// Issue #2987: the AI crawler policy in robots.txt, and an entry's Markdown
// version once it is published. Structural locators only: labels are
// translated and must not be pinned.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function saveSeo(page) {
  await page.getByTestId('submit').click()
  await syncLV(page)
}

test('blocking an AI crawler and refusing training is written into robots.txt', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/config/seo')
  await syncLV(page)

  const crawlers = page.locator('#seo-crawlers')
  const gptbot = crawlers.locator('tr[data-crawler="GPTBot"]')
  const training = crawlers.locator('.seo-crawler-signal')

  await expect(gptbot.locator('input[value="allow"]')).toBeChecked()
  await gptbot.locator('label[data-value="block"]').click()
  await training.locator('label[data-value="no"]').click()
  await expect(crawlers.locator('.seo-crawler-lines pre')).toBeAttached()
  await saveSeo(page)

  const robots = await (await page.request.get('/robots.txt')).text()
  expect(robots).toContain('User-agent: GPTBot\nDisallow: /')
  expect(robots).toContain('Content-Signal: search=yes, ai-input=yes, ai-train=no')
  expect(robots).toContain('Disallow: /admin/')

  await expect(crawlers.locator('a[href$="/robots.txt"]')).toHaveAttribute('target', '_blank')

  // Back to the defaults, which write nothing.
  await gptbot.locator('label[data-value="allow"]').click()
  await training.locator('label[data-value=""]').click()
  await saveSeo(page)
  expect(await (await page.request.get('/robots.txt')).text()).not.toContain('Brando AI crawler policy')
})

test('a published entry is served as Markdown, a draft is not', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Markdown client', slug: 'markdown-client', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Markdown project', slug: 'markdown-project', client_id: client.id, status: 'draft', language: 'en', introduction: '<p>Intro</p>',
  })

  expect((await page.request.get('/project/markdown-project.md')).status()).toBe(404)

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  // The Previews tab names the Markdown address before publishing too.
  await page.locator('button.form-tool-meta').click()
  const drawer = page.locator('.drawer.editor-workspace-drawer').filter({ has: page.locator('[data-testid="meta-tab-previews"]') })
  await drawer.locator('[data-testid="meta-tab-previews"]').click()
  await syncLV(page)
  await expect(drawer).toHaveClass(/previews-open/)
  await expect(drawer.locator('[data-testid="meta-preview-search"]')).toBeVisible()
  await expect(drawer.locator('.meta-preview-markdown-path')).toHaveText('/project/markdown-project.md')
  await expect(drawer.locator('.meta-preview-markdown-text')).toContainText('# Markdown project')
  await page.keyboard.press('Escape')

  await setEntryStatus(page, 'published')
  await page.getByTestId('submit').first().click()
  await syncLV(page)

  await expect.poll(async () => (await page.request.get('/project/markdown-project.md')).status()).toBe(200)
  const markdown = await page.request.get('/project/markdown-project.md')
  expect(markdown.headers()['content-type']).toContain('text/markdown')
  expect(markdown.headers()['vary']).toContain('Accept')
  expect(markdown.headers()['link']).toContain('/project/markdown-project>; rel="canonical"')
  expect(await markdown.text()).toMatch(/^# Markdown project\n/)

  const negotiated = await page.request.get('/project/markdown-project', { headers: { Accept: 'text/markdown' } })
  expect(negotiated.headers()['content-type']).toContain('text/markdown')

  await page.goto('/project/markdown-project')
  await expect(page.locator('link[rel="alternate"][type="text/markdown"]')).toHaveAttribute('href', /\/project\/markdown-project\.md$/)
})
