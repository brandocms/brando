import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate,
  confirmUploadFolder
} from '../../utils'

// Regression guards for two block-editor invariants:
//
//  1. A picked/uploaded picture must remain in the uid-keyed op store when another
//     block is inserted, so rematerializing the editor/preview cannot wipe it.
//
//  2. A gap "+" must derive its insertion point from the current keyed list index
//     after a prior insert; persisted sequence fields are intentionally stale until
//     materialization.
test.describe('Block regressions: media persistence + insert position', () => {
  // Serial — opens a preview channel / renders templates; parallel load can time out.
  test.setTimeout(60000)

  // The bottom "Add block" (append) button and every per-block gap "+" share
  // aria-label="Add block"; the append button is the last one in the DOM.
  const addStyledHeader = async (page) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)
  }

  test('uploaded picture survives inserting another block (live preview)', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Media Persistence Test')
    await page.getByLabel('URI').fill('media-persistence-test')

    // Add a picture block
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Single Image with Caption' }).click()
    await syncLV(page)

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)

    // Upload an image and confirm it renders in the preview
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(2000) // upload + processing
    await waitForPreviewUpdate(page)
    await expect(frame.locator('figure picture').first()).toBeVisible()

    // Regression: inserting another block must NOT drop the uploaded image.
    await addStyledHeader(page)
    await waitForPreviewUpdate(page)

    // The picture must still be present in the preview.
    await expect(frame.locator('figure picture').first()).toBeVisible()
  })

  test('gap "+" inserts at the correct position after a prior insert', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Insert Position Test')
    await page.getByLabel('URI').fill('insert-position-test')

    // Insert a Styled Header via a specific block's gap "+" (renders above that block),
    // then set its text. `entryIndex` is the .entry-block whose gap "+" we click.
    const fillHeader = async (textIndex, text) => {
      const textarea = page.locator('.header-block textarea').nth(textIndex)
      await textarea.fill(text)
      await textarea.blur()
      await syncLV(page)
    }

    const insertHeaderAbove = async (entryIndex, textIndex, text) => {
      await page.locator('.entry-block').nth(entryIndex).locator('.block-plus').first().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)
      await fillHeader(textIndex, text)
    }

    // Start with a single "Anchor" header (appended via the bottom "Add block").
    await addStyledHeader(page)
    await fillHeader(0, 'Anchor')

    // Insert "First" above Anchor → [First, Anchor]
    await insertHeaderAbove(0, 0, 'First')

    // Insert "Second" above Anchor again (Anchor is now the 2nd block) → [First, Second, Anchor].
    // Before the fix Anchor kept a stale sequence, so "Second" landed above "First".
    await insertHeaderAbove(1, 1, 'Second')

    // Order in the editor must be First, Second, Anchor.
    await expect(page.locator('.header-block textarea').nth(0)).toHaveValue('First')
    await expect(page.locator('.header-block textarea').nth(1)).toHaveValue('Second')
    await expect(page.locator('.header-block textarea').nth(2)).toHaveValue('Anchor')
  })
})
