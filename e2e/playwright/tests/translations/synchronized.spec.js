import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A Norwegian source with an English translation (E2EFixtureController
// :synchronized_translation). The source added a block and changed the year,
// so the translation has a pending version.

const noOverflow = page =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

test('a translation opens with its pending version, is reviewed and saved', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/synchronized-translation')
  expect(response.ok()).toBeTruthy()
  const { source_id: sourceId, target_id: targetId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)

  const panel = page.locator('#translation-panel')
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('link', { name: 'Open the source' })).toHaveAttribute('href', `/admin/sync_test/articles/update/${sourceId}`)
  await expect(panel.locator('.translation-group').filter({ hasText: 'Needs translation' })).toContainText('Sync text › Body')
  await expect(panel.locator('.translation-group').filter({ hasText: 'Updated from the source' })).toContainText('Year')
  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })

  // The pending year is in the form, and what follows the source is locked.
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2024')
  await expect(page.locator('#article_year-field-wrapper')).toHaveAttribute('inert', '', { timeout: 5000 })
  await expect(page.locator('.blocks-wrapper.is-source-locked .blocks-source-note')).toBeVisible()
  await expect(page.locator('.blocks-wrapper.is-source-locked .block-plus:visible')).toHaveCount(0)
  await expect(page.locator('[data-sortable-id="article[items]-sortable"]').locator('xpath=ancestor::*[contains(@class,"subform")][1]'))
    .toHaveAttribute('data-source-structure', 'true')
  // The new block, still in Norwegian, is marked.
  await expect(page.locator('.block[data-translation-work]')).toHaveCount(1)
  await page.screenshot({ path: testInfo.outputPath('translation-editor-desktop.png'), fullPage: true })

  // The new text is kept as it is: mark it reviewed. A reconnect keeps the mark.
  const reviewed = panel.getByLabel('Reviewed')
  await reviewed.check()
  await syncLV(page)
  await page.evaluate(() => window.liveSocket.disconnect())
  await page.waitForTimeout(500)
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
  await expect(panel.getByLabel('Reviewed')).toBeChecked({ timeout: 10000 })

  // Meanwhile the source changes the year again.
  const change = await page.request.post('/e2e/synchronized-translation', { data: { source_id: String(sourceId), year: '2030' } })
  expect(change.ok()).toBeTruthy()

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await panel.scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('translation-editor-mobile.png'), fullPage: false })
  await page.setViewportSize({ width: 1440, height: 1000 })

  // Save and continue: what was reviewed is saved, the newer year is loaded.
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  await expect(page.locator('.translation-notice')).toBeVisible({ timeout: 15000 })
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2030', { timeout: 10000 })
  await expect(panel.locator('.translation-group').filter({ hasText: 'Needs translation' })).toHaveCount(0)

  // The listing shows each language and what is still open.
  await page.goto('/admin/sync_test/articles')
  await syncLV(page)
  const versions = page.locator('.listing-translations').first()
  await expect(versions.locator('.listing-translation.is-source')).toContainText('NO')
  await expect(versions.locator(`a[href="/admin/sync_test/articles/update/${targetId}"]`)).toContainText('Updated from the source')
  await page.screenshot({ path: testInfo.outputPath('translation-listing-desktop.png'), fullPage: true })

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('translation-listing-mobile.png'), fullPage: true })

  expect(errors).toEqual([])
})
