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
  await expect(card).toContainText('Live page changes')
  await expect(card.locator('.assistant-card-media img')).toHaveCount(1)
  await page.screenshot({ path: testInfo.outputPath('assistant-review-desktop.png'), fullPage: true })

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
  await page.goto('/admin/assistant')
  await syncLV(page)

  await page.getByRole('button', { name: 'From library' }).click()
  const dialog = page.getByRole('dialog', { name: 'Attach from the media library' })
  await expect(dialog).toBeVisible()
  const first = dialog.locator('.assistant-library-grid button').first()

  if ((await first.count()) === 0) {
    await expect(dialog).toContainText('Nothing matches this search.')
    return
  }

  await first.click()
  await expect(first).toHaveAttribute('aria-pressed', 'true')
  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()

  const attachment = page.locator('.assistant-attachment').first()
  await expect(attachment).toContainText('image1')
  await attachment.hover()
  await attachment.getByRole('button', { name: 'Remove image1' }).click()
  await expect(page.locator('.assistant-attachment')).toHaveCount(0)
})
