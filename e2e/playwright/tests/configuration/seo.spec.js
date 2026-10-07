import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

// The settings preview, saving, and the meta tags, robots.txt and redirects
// the site serves from them are LiveView tests in
// test/brando_admin/live/seo_settings_live_test.exs. What stays here needs a
// browser: uploading the fallback image and the layout at a phone's width.

test('the fallback image uploads into the sharing preview, which fits a phone', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'SEO' }).click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)

  const imageField = page.locator('#seo_fallback_meta_image-media')
  await imageField.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(imageField.locator('img')).toBeVisible({ timeout: 30000 })
  await syncLV(page)
  await expect(page.getByText('No image associated with')).toHaveCount(0)
  await expect(page.locator('.seo-sharing-preview img')).toBeVisible()
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)

  await page.evaluate(() => window.scrollTo(0, 0))
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0)
  await page.screenshot({ path: testInfo.outputPath('seo-populated-desktop.png'), fullPage: true, animations: 'disabled' })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
  await expect(page.locator('.seo-sharing-preview img')).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('seo-populated-mobile.png'), fullPage: true, animations: 'disabled' })
})
