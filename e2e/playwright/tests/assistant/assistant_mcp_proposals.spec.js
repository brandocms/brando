import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Proposals from a tool connected over MCP have no conversation. The fixture
// prepares two the way BrandoMCP does (`Proposals.Tools`, as the admin, from
// "Claude Code"); the Assistant lists them under "From connected tools",
// where one is reviewed, previewed and applied, and the other rejected.

test('reviews, applies and rejects proposals from a connected tool', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/mcp-proposals')
  expect(response.ok()).toBe(true)

  // The Assistant shows how many wait, and opens the list.
  await page.goto('/admin/assistant')
  await syncLV(page)
  const link = page.locator('.assistant-connected-link')
  await expect(link.locator('.assistant-count')).toContainText('2')
  await link.click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected$/)
  await syncLV(page)

  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(2)
  await expect(list.locator('.assistant-badge.is-waiting')).toHaveCount(2)
  await expect(page.locator('#assistant-composer')).toHaveCount(0)

  // Review one: its origin is marked, and its page can be previewed.
  await list.getByRole('link', { name: /Retitle the MCP review page/ }).click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)
  const review = page.locator('.assistant-proposal')
  await expect(review.locator('#assistant-origin .ai-proposal-label')).toContainText('Claude Code')
  await expect(review.locator('.assistant-card')).toHaveCount(1)
  await expect(review.locator('.assistant-card ins')).toContainText('MCP review, from Claude Code')
  await page.screenshot({ path: testInfo.outputPath('assistant-mcp-review.png'), fullPage: true })

  await review.locator('.assistant-card-preview').click()
  await expect(page.locator('.assistant-preview')).toBeVisible()
  await page.locator('.assistant-back').click()
  await expect(review.locator('.assistant-cards')).toBeVisible()

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 15000 })
  await expect(list.locator('.assistant-badge.is-applied')).toHaveCount(1)
  await expect(list.locator('.assistant-badge.is-waiting')).toHaveCount(1)

  // The entry has the new title.
  await review.locator('.assistant-receipt a').first().click()
  await syncLV(page)
  await expect(page.getByLabel('Title', { exact: true })).toHaveValue('MCP review, from Claude Code', { timeout: 15000 })

  // Reject the other: it leaves the list, and its page keeps its title.
  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  await list.getByRole('link', { name: /Retitle the MCP rejected page/ }).click()
  await syncLV(page)
  await review.locator('button.assistant-discard').click()
  await expect(list.locator('li')).toHaveCount(1)
  await expect(list.locator('.assistant-badge.is-waiting')).toHaveCount(0)
  await expect(review.locator('button.assistant-apply')).toHaveCount(0)

  // Nothing waits: the Assistant still links to the list, without a count.
  await page.goto('/admin/assistant')
  await syncLV(page)
  await expect(link).toBeVisible()
  await expect(link.locator('.assistant-count')).toHaveCount(0)

  await page.goto('/admin/pages')
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'MCP rejected', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Should not be applied' })).toHaveCount(0)
  expect(errors).toEqual([])
})
