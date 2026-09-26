import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Runs against E2eProject.AssistantModel: without a page name it works on the
// entry selected in the system prompt, and "all the images in the NAME folder"
// finds the folder and attaches it one image per call.

const noOverflow = page =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

test('Build with AI opens the assistant on the entry, and a folder fills the proposal', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  // Seeded pages are inserted without identifiers; the assistant reads them.
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await page.getByRole('button', { name: 'Sync identifiers' }).click()
  await syncLV(page)

  // A folder with two images.
  await page.goto('/admin/assets/images')
  await syncLV(page)
  await page.getByRole('button', { name: 'New folder', exact: true }).click()
  await page.getByPlaceholder('Folder name', { exact: true }).fill('ai-lobby')
  await page.getByRole('button', { name: 'Create folder', exact: true }).click()
  await expect(page.getByRole('navigation', { name: 'Folder path' })).toContainText('ai-lobby')
  await page.getByLabel('Upload images', { exact: true }).setInputFiles(['./fixtures/image2.jpg', './fixtures/image.jpg'])
  await expect(page.locator('.content-list .list-row')).toHaveCount(2, { timeout: 30000 })

  // The block editor offers the assistant beside the field.
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  const action = page.getByTestId('build-with-ai').first()
  await expect(action).toBeVisible({ timeout: 15000 })
  await expect(action).toHaveAttribute('target', '_blank')
  await action.scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('build-with-ai-desktop.png') })

  // It opens in a new tab, so the editor stays as it is.
  const [assistant] = await Promise.all([page.waitForEvent('popup'), action.click()])
  assistant.on('pageerror', error => errors.push(error.message))
  await assistant.setViewportSize({ width: 1440, height: 1000 })
  await assistant.waitForLoadState()
  await syncLV(assistant)
  await expect(page).toHaveURL(/\/admin\/pages\/update\/1$/)

  const destination = assistant.locator('#assistant-destination')
  await expect(destination).toContainText('Working on')
  await expect(destination).toContainText('Blocks')
  await expect(destination).toContainText('The assistant reads the saved entry')
  const title = (await destination.locator('.assistant-destination-title').innerText()).trim()

  const input = assistant.getByLabel('Message')
  await input.fill('Use all the images in the ai-lobby folder here')
  await input.press('Enter')
  await expect(assistant).toHaveURL(/\/admin\/assistant\/[0-9a-f-]{36}$/)

  // Two calls attach the folder, one page each, as image1 and image2.
  const steps = assistant.locator('.assistant-steps')
  await expect(steps).toContainText('Looked for the folder', { timeout: 15000 })
  await expect(steps.getByText("Attached the folder's media")).toHaveCount(2)
  const attachments = assistant.locator('.assistant-attachment')
  await expect(attachments).toHaveCount(2)
  await expect(attachments.nth(0)).toContainText('image1')
  await expect(attachments.nth(1)).toContainText('image2')

  // The proposal is for the selected entry and places both images.
  await expect(assistant.locator('.assistant-text').last()).toContainText(`adds image1, image2 to ${title}`, { timeout: 15000 })
  const review = assistant.locator('.assistant-proposal')
  await expect(review.getByRole('heading', { name: 'Ready for your review' })).toBeVisible()
  const card = review.locator('.assistant-card')
  await expect(card).toHaveCount(1)
  await expect(card).toContainText(title)
  await expect(card.locator('.assistant-changes > li')).toHaveCount(2)
  await expect(assistant.locator('.assistant-attachment.is-used')).toHaveCount(2)
  await expect(destination).toContainText(title)
  await assistant.screenshot({ path: testInfo.outputPath('assistant-entry-folder-desktop.png'), fullPage: true })

  await assistant.setViewportSize({ width: 390, height: 844 })
  await assistant.waitForTimeout(300)
  expect(await noOverflow(assistant)).toBeLessThanOrEqual(0)
  await destination.scrollIntoViewIfNeeded()
  await assistant.screenshot({ path: testInfo.outputPath('assistant-entry-folder-mobile.png'), fullPage: true })

  await page.setViewportSize({ width: 390, height: 844 })
  await action.scrollIntoViewIfNeeded()
  await expect(action).toBeVisible()
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('build-with-ai-mobile.png') })

  // Nothing was applied: the proposal waits for review.
  await expect(assistant.getByRole('button', { name: /Apply 1 entry change/ })).toBeVisible()
  expect(errors).toEqual([])
})
