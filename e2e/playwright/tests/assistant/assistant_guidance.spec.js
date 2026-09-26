import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

const noOverflow = page =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

test('a superuser keeps the assistant guidance, and editors can read it', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  await page.goto('/admin/config/assistant')
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'Assistant guidance', level: 1 })).toBeVisible()
  await expect(page.getByText('No guidance has been saved here yet.')).toBeVisible()

  const save = page.getByRole('button', { name: 'Save guidance' })
  await expect(save).toBeDisabled()
  const text = page.locator('#guidance-text')
  await text.fill('Start an article with the Article lede module.')
  await expect(page.locator('.guidance-count')).toContainText('46 of')
  await expect(save).toBeEnabled()
  await save.click()
  await expect(page.locator('.guidance-history li')).toHaveCount(1)
  await expect(page.locator('.guidance-history li')).toContainText('In use')

  await text.fill('Start an article with the Article lede module.\nPortrait pairs use Two images with narrow on.')
  await expect(page.locator('.guidance-count')).toContainText('92 of')
  await save.click()
  await expect(page.locator('.guidance-history li')).toHaveCount(2)
  await expect(page.locator('.guidance-saved')).toContainText('Saved')
  await page.screenshot({ path: testInfo.outputPath('guidance-desktop.png'), fullPage: true })

  // An earlier version comes back through the editor.
  await page.locator('.guidance-history li').nth(1).getByRole('button', { name: 'Load into editor' }).click()
  await expect(text).toHaveValue('Start an article with the Article lede module.')
  await expect(page.locator('.guidance-note')).toContainText('Restored the version from')
  await page.getByRole('button', { name: 'Discard changes' }).click()
  await expect(text).toHaveValue(/Portrait pairs/)

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('guidance-mobile.png'), fullPage: true })

  // Editors see what steers the assistant.
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/assistant')
  await syncLV(page)
  const guidance = page.locator('#assistant-guidance')
  await guidance.getByText('Site guidance in use').click()
  await expect(guidance.locator('pre')).toContainText('Portrait pairs use Two images with narrow on.')
  await expect(guidance.getByRole('link', { name: 'Edit guidance' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('assistant-guidance-desktop.png') })

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-guidance-mobile.png') })
  expect(errors).toEqual([])
})
