import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

/**
 * Opens the block action dropdown and clicks the Copy button.
 * @param {import('@playwright/test').Locator} scope - A locator scoped to the block element
 */
async function copyBlock(scope) {
  await scope.locator('.block-action-dropdown > .block-action').click()
  await scope.locator('.block-action-dropdown-content button', { hasText: 'Copy' }).click()
}

async function openPage(page, title) {
  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: title }).click()
  await syncLV(page)
}

async function savePage(page) {
  await page.getByTestId('submit').click()
  await expect(page).not.toHaveURL(/\/(create|update\/\d+)$/, { timeout: 30000 })
  await syncLV(page)
}

// Images, videos and files are library assets: a copied block points at the
// same ones on purpose. A gallery is not — it is owned by the ref that points
// at it, so copying a block has to give the copy its own gallery row. Sharing
// one row means removing an image from the copy removes it from the original,
// which is at its most destructive across entries, where the original is not
// even on screen to show what just happened.
test.describe('Gallery copy independence', () => {
  test.describe.configure({ mode: 'serial' })

  test('a gallery block pasted into another entry gets its own gallery', async ({ page }) => {
    test.setTimeout(240000)

    // --- Source entry: a gallery block with two images ---
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Gallery Copy Source')
    await page.getByLabel('URI').fill('gallery-copy-source')

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    await page
      .locator('.gallery-block .file-input')
      .setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
    await confirmUploadFolder(page)
    await syncLV(page)

    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 20000,
    })

    await savePage(page)

    // --- Target entry: paste the copied block ---
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Gallery Copy Target')
    await page.getByLabel('URI').fill('gallery-copy-target')
    await savePage(page)

    await openPage(page, 'Gallery Copy Source')
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 20000,
    })
    await copyBlock(page.locator('.entry-block').first())
    await syncLV(page)

    await openPage(page, 'Gallery Copy Target')
    const bottomPaste = page.locator('.blocks-content > .block-plus-wrapper .block-paste')
    await expect(bottomPaste).toBeVisible()
    await bottomPaste.click()
    await syncLV(page)

    // The copy carries the same media across
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 20000,
    })
    await savePage(page)

    // --- Remove one image from the COPY ---
    await openPage(page, 'Gallery Copy Target')
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 20000,
    })
    await page.locator('.gallery-block .gallery-object .delete-x').first().click()
    await syncLV(page)
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 10000,
    })
    await savePage(page)

    // --- The original is untouched ---
    await openPage(page, 'Gallery Copy Source')
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 20000,
    })

    // and the copy kept its own single image
    await openPage(page, 'Gallery Copy Target')
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 20000,
    })
  })
})
