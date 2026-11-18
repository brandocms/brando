import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A Norwegian source with one block and one item (E2EFixtureController
// :synchronized_translation, source_only), translated from its own form. The
// new translation still holds the source's text, and lists all of it as
// needing translation.

test('a new translation lists the text it copied as needing translation', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/synchronized-translation', { data: { source_only: 'true' } })
  expect(response.ok()).toBeTruthy()
  const { source_id: sourceId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)
  await page.locator('.translation-create').getByRole('button', { name: 'English' }).click()

  const panel = page.locator('#translation-panel')
  await expect(panel).toBeVisible({ timeout: 10000 })
  await expect(page).not.toHaveURL(new RegExp(`/update/${sourceId}$`))
  await syncLV(page)

  // The title, the block's text and the item's label, still in Norwegian
  const translate = panel.locator('.translation-group').filter({ hasText: 'Needs translation' })
  await expect(translate.locator('li')).toHaveCount(3)
  await expect(translate).toContainText('Sync text › Body')
  await expect(panel.locator('.translation-done')).toHaveCount(0)
  await expect(page.locator('.block[data-translation-work]')).toHaveCount(1)
  await panel.screenshot({ path: testInfo.outputPath('new-translation-panel.png') })

  // Marked reviewed, a text needs no change; the rest stays open after the save.
  await translate.locator('li').first().getByLabel('Reviewed').check()
  await syncLV(page)
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  await expect(translate.locator('li')).toHaveCount(2, { timeout: 15000 })

  expect(errors).toEqual([])
})
