import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A connected tool's proposal to replace an image's file
// (`replace_image_file`). The fixture prepares it as BrandoMCP does: the
// Index page's share image, also two projects' listing image, takes the file
// of a better copy. The review shows both files side by side with their
// dimensions and the three entries that show the image; once applied, the
// image shows the new file and the proposal has no undo.

const openProposal = async page => {
  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  await page.locator('#assistant-connected-list li a').first().click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)
  return page.locator('.assistant-proposal')
}

test('reviews and applies the replacement of an image file', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/mcp-image-replacement')
  expect(response.ok()).toBe(true)

  const review = await openProposal(page)
  const card = review.locator('.assistant-replacement')
  await expect(card).toHaveCount(1)
  await expect(card.getByTestId('assistant-action-replace-file')).toBeVisible()

  // Both files, whole, with their dimensions
  const old = card.locator('.assistant-replacement-file.is-old img')
  const proposed = card.locator('.assistant-replacement-file.is-new img')
  await expect(old).toHaveAttribute('width', '1600')
  await expect(old).toHaveAttribute('height', '1200')
  await expect(proposed).toHaveAttribute('width', '2400')
  await expect(proposed).toHaveAttribute('height', '1800')
  await expect.poll(() => old.evaluate(img => img.complete && img.naturalWidth)).toBeGreaterThan(0)
  await expect.poll(() => proposed.evaluate(img => img.complete && img.naturalWidth)).toBeGreaterThan(0)
  const oldName = await card.locator('.assistant-replacement-file.is-old .assistant-replacement-name').textContent()

  // The three entries that show it, linked; the same proportions, no warning
  await expect(card.locator('.assistant-replacement-uses li a')).toHaveCount(3)
  await expect(card.locator('.assistant-replacement-uses a[href^="/admin/pages/update/"]')).toHaveCount(1)
  await expect(card.locator('.assistant-feedback.is-warning')).toHaveCount(0)
  await expect(review.locator('.assistant-cards .assistant-card:not(.assistant-replacement)')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-image-replacement.png'), fullPage: true })

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 15000 })
  await expect(review.getByTestId('assistant-receipt-badge')).toHaveCount(1)
  await expect(review.locator('button.assistant-undo')).toHaveCount(0)

  // Applied, the card still shows the two files as they were
  await expect(card.locator('.assistant-replacement-file.is-old .assistant-replacement-name')).toHaveText(oldName)

  expect(errors).toEqual([])
})

test('warns when the new file has other proportions', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const response = await page.request.post('/e2e/setup_fixtures/mcp-image-replacement-wide')
  expect(response.ok()).toBe(true)

  const review = await openProposal(page)
  const card = review.locator('.assistant-replacement')
  await expect(card.locator('.assistant-replacement-file.is-new img')).toHaveAttribute('height', '1350')
  await expect(card.locator('.assistant-feedback.is-warning')).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('assistant-image-replacement-wide.png'), fullPage: true })

  // At phone width the two files stay side by side, inside the card
  await page.setViewportSize({ width: 390, height: 900 })
  const box = await card.boundingBox()
  const files = await card.locator('.assistant-replacement-files').boundingBox()
  expect(files.x + files.width).toBeLessThanOrEqual(box.x + box.width + 1)
})
