import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Gallery block image replacement', () => {
  test.describe.configure({ mode: 'serial' })

  test('can remove an image and add another, then save successfully', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Gallery Replace Test')
    await page.getByLabel('URI').fill('gallery-replace-test')

    // Add a Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload 2 images to the gallery block
    await page
      .locator('.gallery-block .file-input')
      .setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
    await syncLV(page)
    await page.waitForTimeout(3000)

    // Wait for both gallery objects to appear
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 15000,
    })

    // Remove the first image using the delete-x button
    await page.locator('.gallery-block .gallery-object .delete-x').first().click()
    await syncLV(page)

    // Only 1 image should remain
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 5000,
    })

    // Upload a new image to replace the removed one
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await syncLV(page)
    await page.waitForTimeout(3000)

    // Should have 2 images again
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 15000,
    })

    // Save the page — this is the operation that previously failed
    await page.getByRole('button', { name: 'Save' }).click()
    await syncLV(page)

    // Verify save succeeded — no error alert should appear
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    // Verify the page was saved by checking we're no longer on the create page
    // (redirects to edit page on successful save)
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 5000 })
  })
})
