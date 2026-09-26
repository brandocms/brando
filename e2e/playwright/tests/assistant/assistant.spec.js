import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The assistant runs against E2eProject.AssistantModel, a scripted model that
// drives the real tools: search → modules → attachments → prepare_proposal.

test('uploads media, prepares a proposal from a message and applies it', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  // Seeded pages are inserted without identifiers; entry search reads them.
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await page.getByRole('button', { name: 'Sync identifiers' }).click()
  await syncLV(page)

  await page.goto('/admin/assistant')
  await syncLV(page)

  await expect(page.getByRole('heading', { name: 'Assistant', level: 1 })).toBeVisible()
  await expect(page.getByRole('heading', { name: 'No proposal yet' })).toBeVisible()

  // Uploading through the sticky UploadManager reserves image1 at intake and
  // fills it in when the upload completes.
  await page.locator('#assistant-upload input.file-input').setInputFiles('./fixtures/image.jpg')
  const attachment = page.locator('.assistant-attachment').filter({ hasText: 'image1' })
  await expect(attachment).toBeVisible({ timeout: 15000 })
  await expect(attachment).not.toHaveClass(/is-pending/, { timeout: 30000 })
  await expect(page).toHaveURL(/\/admin\/assistant\/[0-9a-f-]{36}$/)

  const input = page.getByLabel('Message')
  await input.fill('Put image1 on the Index page')
  await input.press('Enter')

  await expect(page.locator('.assistant-bubble')).toHaveText('Put image1 on the Index page')
  await expect(page.locator('.assistant-steps')).toContainText('Searched for “Index”', { timeout: 15000 })
  await expect(page.locator('.assistant-steps')).toContainText('Prepared the proposal')
  await expect(page.locator('.assistant-text').last()).toContainText('I prepared a proposal that adds image1 to Index')

  const review = page.locator('.assistant-proposal')
  await expect(review.getByRole('heading', { name: 'Ready for your review' })).toBeVisible()
  const card = review.locator('.assistant-card').filter({ hasText: 'Index' })
  await expect(card).toContainText('Add a Single Asset block')
  await expect(card).toContainText('At the end')
  await expect(card).toContainText('Live page')
  await expect(card.locator('.assistant-card-cover img')).toHaveCount(1)
  await page.screenshot({ path: testInfo.outputPath('assistant-review-desktop.png'), fullPage: true })

  // The page preview renders the proposed page in the site's own template and
  // outlines the new block outside the page's content.
  await card.getByRole('button', { name: 'Preview page' }).click()
  await expect(review.getByRole('heading', { name: 'Page preview' })).toBeVisible()
  const frame = page.frameLocator('.assistant-frame iframe')
  await expect(frame.locator('.brando-proposal-highlight')).toHaveCount(1, { timeout: 15000 })
  await expect(frame.locator('article[b-tpl="asset"] img, article[b-tpl="asset"] picture').first()).toBeAttached()
  await page.waitForTimeout(500)
  await page.screenshot({ path: testInfo.outputPath('assistant-preview-desktop.png') })

  await review.getByRole('button', { name: 'Before' }).click()
  await expect(review.locator('.assistant-frame-bar')).toContainText('Saved version')
  await expect(frame.locator('article[b-tpl="asset"]')).toHaveCount(0, { timeout: 15000 })
  await expect(frame.locator('.brando-proposal-highlight')).toHaveCount(0)

  await review.getByRole('button', { name: 'Proposed' }).click()
  await review.getByRole('button', { name: 'Mobile' }).click()
  await expect(page.locator('.assistant-frame iframe')).toHaveCSS('width', '390px')
  await review.getByRole('button', { name: 'All changes' }).click()
  await expect(review.locator('.assistant-card')).toHaveCount(1)

  // A refinement replaces the proposal with version 2.
  await input.fill('Put image1 on the Index page instead')
  await input.press('Enter')
  await expect(review.locator('.assistant-eyebrow')).toContainText('version 2', { timeout: 15000 })

  const apply = page.getByRole('button', { name: 'Apply 1 entry change · affects 1 live page' })
  await expect(apply).toBeEnabled()
  await apply.click()
  await expect(review.getByRole('heading', { name: 'Applied' })).toBeVisible({ timeout: 15000 })
  await expect(review.locator('.assistant-receipt')).toContainText('Index')
  await expect(page.getByRole('button', { name: /Apply/ })).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-applied-desktop.png'), fullPage: true })

  // The conversation is kept and listed.
  await page.getByRole('button', { name: 'Recent conversations' }).click()
  await expect(page.locator('#assistant-history-list')).toContainText('Put image1 on the Index page')

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-applied-mobile.png'), fullPage: true })
  expect(errors).toEqual([])
})

test('attaches library media and removes it again', async ({ page }) => {
  const response = await page.request.post('/e2e/admin-workspace-fixtures')
  expect(response.ok()).toBeTruthy()
  await page.goto('/admin/assistant')
  await syncLV(page)

  await page.getByTitle('Attach videos from the media library', { exact: true }).click()
  const dialog = page.locator('#video-picker')
  await expect(dialog).toBeVisible()
  const video = dialog.locator('.video-picker__video').filter({ hasText: 'Studio tour' })

  await video.click()
  await expect(video).toHaveClass(/selected/)
  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()

  const attachment = page.locator('.assistant-attachment').first()
  await expect(attachment).toContainText('video1')
  await attachment.hover()
  await attachment.getByRole('button', { name: 'Remove video1' }).click()
  await expect(page.locator('.assistant-attachment')).toHaveCount(0)
})
