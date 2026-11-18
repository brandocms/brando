import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A Norwegian source whose block has an empty media ref (E2EFixtureController
// :synchronized_translation_refs), and its English synchronized translation.
// Media follows the source, so the translation's empty media ref explains
// that instead of offering media types.

test('an empty media ref says why it is empty in a synchronized translation', async ({ page }) => {
  const response = await page.request.post('/e2e/synchronized-translation-refs')
  expect(response.ok()).toBeTruthy()
  const { source_id: sourceId, target_id: targetId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)

  const translated = page.locator('.blocks-wrapper.is-source-locked [b-ref="cover"] .media-block .empty')
  await expect(translated.locator('.media-block-source-note')).toBeVisible()
  await expect(translated.locator('.instructions')).toBeHidden()
  await expect(translated.locator('button:visible')).toHaveCount(0)

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)

  const source = page.locator('[b-ref="cover"] .media-block .empty')
  await expect(source.locator('.instructions')).toBeVisible()
  await expect(source.locator('button[phx-value-block]')).toHaveCount(2)
  await expect(source.locator('.media-block-source-note')).toBeHidden()

  // A one-line and a multi-line variable with the default layout: full
  // width, each on a row of its own
  const rows = page.locator('.block-vars .block-vars-row')
  await expect(rows).toHaveCount(2)
  await expect(rows.nth(0).locator('.variable')).toHaveAttribute('data-size', 'full')
  await expect(rows.nth(1).locator('.variable.text')).toHaveAttribute('data-size', 'full')
})
