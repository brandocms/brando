import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Assistant → From connected tools stays open while a connected tool works.
// The fixture connects Claude as the E2E admin and stores one proposal
// through the endpoint's tools; "-next" stores the tool's newer version of
// it and a proposal about another page, as the tool would while the person
// reads the first.

test('the review list follows a connected tool, and keeps the proposal under review', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  expect((await page.request.post('/e2e/setup_fixtures/mcp-live-review')).ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(1)
  await expect(list.getByTestId('assistant-connected-live')).toHaveAttribute('href', /\/admin\/assistant\/connected\/live\/\d+$/)

  await list.getByRole('link', { name: /Retitle the Index page/ }).click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)
  const firstUrl = page.url()
  const review = page.locator('.assistant-proposal')
  await expect(review.locator('.assistant-summary')).toHaveText('Retitle the Index page')
  await expect(review.locator('button.assistant-apply')).toBeEnabled()

  // The tool works on: both appear without a reload
  expect((await page.request.post('/e2e/setup_fixtures/mcp-live-review-next')).ok()).toBe(true)
  await expect(list.getByRole('link', { name: /Retitle the Visit page/ })).toBeVisible()
  await expect(list.getByRole('link', { name: /Retitle the Index page, shorter/ })).toBeVisible()
  await expect(list.locator('li')).toHaveCount(2)

  // The proposal being read stays, with Approve withdrawn and a line saying why
  const stale = page.locator('#assistant-stale')
  await expect(stale).toContainText('A newer version of this proposal arrived')
  await expect(page).toHaveURL(firstUrl)
  await expect(review.locator('.assistant-summary')).toHaveText('Retitle the Index page')
  await expect(review.locator('button.assistant-apply')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-live-review-stale.png'), fullPage: true })

  // Until the person asks for the newer one
  await stale.getByRole('link', { name: 'Show it' }).click()
  await expect(page).not.toHaveURL(firstUrl)
  await syncLV(page)
  await expect(review.locator('.assistant-summary')).toHaveText('Retitle the Index page, shorter')
  await expect(page.locator('#assistant-stale')).toHaveCount(0)
  await expect(review.locator('button.assistant-apply')).toBeEnabled()
  expect(errors).toEqual([])
})
