import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Save → reload persistence guards for block media.
//
// The recurring bug class in the block editor is media that LOOKS attached
// (renders in the editor and live preview) but is silently lost by the time
// it reaches the database: uploads followed directly by save, block-list
// changes (insert/delete) re-initialising siblings from a stale parent cache
// and wiping a just-set FK, and propagation clobbering un-propagated sibling
// edits. Earlier specs stopped at "save didn't error" or at the live preview —
// these reopen the entry and assert the media actually persisted.
test.describe('Block media save persistence', () => {
  test.describe.configure({ mode: 'serial' })

  const createPage = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)
  }

  // The bottom "Add block" (append) button and per-block gap "+" share the
  // same label; the append button is last in the DOM.
  const appendBlock = async (page, moduleName) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: moduleName }).click()
    await syncLV(page)
  }

  const uploadPicture = async (page) => {
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await syncLV(page)
    // upload + processing; the block swaps the upload canvas for the image
    await expect(page.locator('.picture-block img:visible').first()).toBeVisible({ timeout: 20000 })
  }

  const saveAndReopen = async (page, title) => {
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${title} →` }).click()
    await syncLV(page)
  }

  // NOTE: each test runs in its own SQL sandbox — entries created in one test
  // do not exist in the next, so the full create → save → reload → edit →
  // save → reload lifecycle lives in a single test.
  test('uploaded picture survives insert + save + reload, then an edit + save cycle', async ({
    page,
  }) => {
    test.setTimeout(180000)

    await createPage(page, 'Persist Insert Test', 'persist-insert-test')
    await appendBlock(page, 'Single Image with Caption')
    await uploadPicture(page)

    // Stale-cache regression: inserting another block re-initialises siblings
    // from the parent's cached forms — this must not wipe the picture's FK.
    await appendBlock(page, 'Styled Header')

    await saveAndReopen(page, 'Persist Insert Test')

    // The image must still be attached after a full round-trip through the DB.
    await expect(page.locator('.picture-block img:visible').first()).toBeVisible({
      timeout: 20000,
    })

    // Now edit an unrelated block on the EXISTING entry and save again — the
    // edit/save cycle must not lose the previously persisted media.
    await page.locator('.header-block textarea').first().fill('Edited after reload')
    await syncLV(page)

    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: 'Persist Insert Test →' }).click()
    await syncLV(page)

    await expect(page.locator('.picture-block img:visible').first()).toBeVisible({
      timeout: 20000,
    })
    await expect(page.locator('.header-block textarea').first()).toHaveValue(
      'Edited after reload'
    )
  })

  test('uploaded picture survives deleting another block, then save + reload', async ({
    page,
  }) => {
    test.setTimeout(120000)

    await createPage(page, 'Persist Delete Test', 'persist-delete-test')
    await appendBlock(page, 'Styled Header')
    await page.locator('.header-block textarea').first().fill('Doomed header')
    await syncLV(page)

    await appendBlock(page, 'Single Image with Caption')
    await uploadPicture(page)

    // Delete the header block via its action dropdown — the resulting
    // re-render must not re-initialise the picture block from a stale cache.
    const headerBlock = page.locator('.entry-block').first()
    await headerBlock.locator('.block-action-dropdown > .block-action').click()
    await headerBlock
      .locator('.block-action-dropdown-content button', { hasText: 'Delete' })
      .click()
    await syncLV(page)

    await expect(page.locator('.header-block')).not.toBeVisible({ timeout: 5000 })
    await expect(page.locator('.picture-block img:visible').first()).toBeVisible()

    await saveAndReopen(page, 'Persist Delete Test')

    await expect(page.locator('.picture-block img:visible').first()).toBeVisible({ timeout: 20000 })
    await expect(page.locator('.header-block')).not.toBeVisible()
  })

  test('upload in one block does not clobber unsaved text in another', async ({ page }) => {
    test.setTimeout(120000)

    await createPage(page, 'Persist Clobber Test', 'persist-clobber-test')

    // Block A: header with UNSAVED text (never propagated to the parent cache)
    await appendBlock(page, 'Styled Header')
    await page.locator('.header-block textarea').first().fill('Unsaved sibling text')
    await syncLV(page)

    // Block B: picture upload — its delivery propagates (update_ref_data
    // propagate: true), which pushes the parent's cached forms back down to
    // every sibling. That push must not clobber block A's local edits.
    await appendBlock(page, 'Single Image with Caption')
    await uploadPicture(page)

    await expect(page.locator('.header-block textarea').first()).toHaveValue(
      'Unsaved sibling text'
    )

    await saveAndReopen(page, 'Persist Clobber Test')

    await expect(page.locator('.header-block textarea').first()).toHaveValue(
      'Unsaved sibling text',
      { timeout: 20000 }
    )
    await expect(page.locator('.picture-block img:visible').first()).toBeVisible({ timeout: 20000 })
  })
})
