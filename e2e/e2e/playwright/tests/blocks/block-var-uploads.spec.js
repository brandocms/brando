import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Render var uploads', () => {
  test.describe.configure({ mode: 'serial' })

  test('can upload an image through an image var and save', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Var Upload Test')
    await page.getByLabel('URI').fill('var-upload-test')

    // Add the Image and File Vars module
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
    await page.getByRole('button', { name: 'Image and File Vars' }).click()
    await syncLV(page)

    // Click "Add image" to open the image modal
    const addImageButton = page.getByRole('button', { name: 'Add image' })
    await expect(addImageButton).toBeVisible({ timeout: 5000 })
    await addImageButton.click()

    // The image modal should be visible — use :visible pseudo to pick the shown one
    const imageModal = page.locator('[id$="image-config"]:visible')
    await expect(imageModal).toBeVisible({ timeout: 5000 })

    // Upload an image via the file input in the modal
    const imageFileInput = imageModal.locator('input[type="file"].file-input')
    await imageFileInput.setInputFiles('./fixtures/image.jpg')

    // Wait for upload and processing to complete
    // The upload canvas should disappear and be replaced by an img element
    await expect(imageModal.locator('img')).toBeVisible({ timeout: 20000 })

    // Verify image info is displayed
    await expect(imageModal.locator('.image-info')).toBeVisible()

    // Close the modal
    await imageModal.locator('button.modal-close').click()
    await syncLV(page)

    // The block should now show the image preview with "Edit image" button
    await expect(page.getByRole('button', { name: 'Edit image' })).toBeVisible({ timeout: 5000 })

    // Save the page
    await page.getByRole('button', { name: 'Save' }).click()
    await syncLV(page)

    // Verify save succeeded
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 5000 })
  })

  test('can upload a file through a file var and save', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Var File Upload Test')
    await page.getByLabel('URI').fill('var-file-upload-test')

    // Add the Image and File Vars module
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
    await page.getByRole('button', { name: 'Image and File Vars' }).click()
    await syncLV(page)

    // Click "Add file" to open the file modal
    const addFileButton = page.getByRole('button', { name: 'Add file' })
    await expect(addFileButton).toBeVisible({ timeout: 5000 })
    await addFileButton.click()

    // The file modal should be visible
    const fileModal = page.locator('[id$="file-config"]:visible')
    await expect(fileModal).toBeVisible({ timeout: 5000 })

    // Upload a file via the file input in the modal
    const fileInput = fileModal.locator('input[type="file"].file-input')
    await fileInput.setInputFiles('./fixtures/test.pdf')

    // Wait for upload and processing to complete
    // The upload canvas should disappear and be replaced by file info
    await expect(fileModal.locator('.file-info')).toBeVisible({ timeout: 20000 })

    // Close the modal
    await fileModal.locator('button.modal-close').click()
    await syncLV(page)

    // The block should now show the file preview with "Edit file" button
    await expect(page.getByRole('button', { name: 'Edit file' })).toBeVisible({ timeout: 5000 })

    // Save the page
    await page.getByRole('button', { name: 'Save' }).click()
    await syncLV(page)

    // Verify save succeeded
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 5000 })
  })

  test('can reset an uploaded image var', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Var Reset Image Test')
    await page.getByLabel('URI').fill('var-reset-image-test')

    // Add the Image and File Vars module
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
    await page.getByRole('button', { name: 'Image and File Vars' }).click()
    await syncLV(page)

    // Upload an image first
    const addImageButton = page.getByRole('button', { name: 'Add image' })
    await addImageButton.click()

    const imageModal = page.locator('[id$="image-config"]:visible')
    await expect(imageModal).toBeVisible({ timeout: 5000 })
    await imageModal.locator('input[type="file"].file-input').setInputFiles('./fixtures/image.jpg')
    await expect(imageModal.locator('img')).toBeVisible({ timeout: 20000 })

    // Click "Reset image" button in the modal
    await imageModal.getByRole('button', { name: 'Reset image' }).click()
    await syncLV(page)

    // The upload canvas should be back (image was removed)
    await expect(imageModal.locator('.upload-canvas')).toBeVisible({ timeout: 5000 })

    // Close modal
    await imageModal.locator('button.modal-close').click()
    await syncLV(page)

    // The block should show "Add image" again
    await expect(page.getByRole('button', { name: 'Add image' })).toBeVisible({ timeout: 5000 })
  })

  test('can reset an uploaded file var', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Var Reset File Test')
    await page.getByLabel('URI').fill('var-reset-file-test')

    // Add the Image and File Vars module
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
    await page.getByRole('button', { name: 'Image and File Vars' }).click()
    await syncLV(page)

    // Upload a file first
    const addFileButton = page.getByRole('button', { name: 'Add file' })
    await addFileButton.click()

    const fileModal = page.locator('[id$="file-config"]:visible')
    await expect(fileModal).toBeVisible({ timeout: 5000 })
    await fileModal.locator('input[type="file"].file-input').setInputFiles('./fixtures/test.pdf')
    await expect(fileModal.locator('.file-info')).toBeVisible({ timeout: 20000 })

    // Click "Reset file" button in the modal
    await fileModal.getByRole('button', { name: 'Reset file' }).click()
    await syncLV(page)

    // The upload canvas should be back (file was removed)
    await expect(fileModal.locator('.upload-canvas')).toBeVisible({ timeout: 5000 })

    // Close modal
    await fileModal.locator('button.modal-close').click()
    await syncLV(page)

    // The block should show "Add file" again
    await expect(page.getByRole('button', { name: 'Add file' })).toBeVisible({ timeout: 5000 })
  })
})
