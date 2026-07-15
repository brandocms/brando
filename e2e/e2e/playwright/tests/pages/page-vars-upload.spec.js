import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

// Entry-level vars (page variables under the Advanced tab) have no owning
// block component — their FK commits ride the `b:validate` contract into the
// entry changeset. Regression: with no on_change wired, an image pick looked
// applied locally but never reached the changeset until an unrelated
// validate, and a reset was silently lost entirely (the hidden input fell
// back to the stale changeset value on the next patch).
test.describe('Entry-level page var uploads', () => {
  test.describe.configure({ mode: 'serial' })

  const createPageWithImageVar = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    // The page vars subform lives under the Advanced tab
    await page.getByRole('button', { name: 'Advanced' }).click()
    await page.getByRole('button', { name: 'Add entry' }).click()
    await syncLV(page)

    // Expand the new var entry and switch its type to image
    const entry = page.locator('.subform-entry').first()
    await entry.locator('.variable-header').click()
    await entry.locator('.field-wrapper:has-text("Type") .button-edit').click()
    await entry.locator('.options-option:has-text("Image")').click()
    await syncLV(page)

    // The select stores its choice in a hidden input — editing the key
    // triggers the form validate that materializes the type change
    await entry.getByLabel('Key', { exact: true }).fill('hero_image')
    await entry.getByLabel('Key', { exact: true }).blur()
    await syncLV(page)

    // Open the image modal from the (empty) preview and upload
    await entry.getByRole('button', { name: 'Add image' }).click()
    const imageModal = page.locator('[id$="image-config"]:visible')
    await expect(imageModal).toBeVisible({ timeout: 5000 })
    await imageModal.locator('input[type="file"].file-input').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await expect(imageModal.locator('img')).toBeVisible({ timeout: 20000 })

    return { entry, imageModal }
  }

  const saveAndReopen = async (page, title) => {
    await page.getByRole('button', { name: 'Save' }).click()
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 10000 })

    await page.getByRole('link', { name: `${title} →` }).click()
    await syncLV(page)
    await page.getByRole('button', { name: 'Advanced' }).click()
    await syncLV(page)

    const entry = page.locator('.subform-entry').first()
    await entry.locator('.variable-header').click()
    return entry
  }

  test('image picked for an entry-level var persists through save + reload', async ({ page }) => {
    test.setTimeout(120000)

    const { imageModal } = await createPageWithImageVar(page, 'Page Var Image', 'page-var-image')

    await imageModal.locator('button.modal-close').click()
    await syncLV(page)

    const entry = await saveAndReopen(page, 'Page Var Image')

    // The var preview must show the persisted image
    await expect(entry.getByRole('button', { name: 'Edit image' })).toBeVisible({ timeout: 20000 })
  })

  test('reset of an entry-level image var persists through save + reload', async ({ page }) => {
    test.setTimeout(120000)

    const { imageModal } = await createPageWithImageVar(page, 'Page Var Reset', 'page-var-reset')

    // Reset the image in the modal, then save
    await imageModal.getByRole('button', { name: 'Reset image' }).click()
    await syncLV(page)
    await expect(imageModal.locator('.upload-canvas')).toBeVisible({ timeout: 5000 })
    await imageModal.locator('button.modal-close').click()
    await syncLV(page)

    const entry = await saveAndReopen(page, 'Page Var Reset')

    // The reset must have persisted — no image on the var after reload
    await expect(entry.getByRole('button', { name: 'Add image' })).toBeVisible({ timeout: 10000 })
    await expect(entry.getByRole('button', { name: 'Edit image' })).not.toBeVisible()
  })
})
