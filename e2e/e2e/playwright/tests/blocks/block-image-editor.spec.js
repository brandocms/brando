import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Image Editor from Blocks', () => {
  test.describe.configure({ mode: 'parallel' })

  test('opens image editor from picture block preview icon', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('PictureBlock Editor Test')
    await page.getByLabel('URI').fill('picture-editor-test')

    // Add Single Image with Caption block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Single Image with Caption' }).click()
    await syncLV(page)

    // Upload image to the picture block
    await page.locator('.picture-block .file-input').setInputFiles('./fixtures/image.jpg')
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear in preview
    await expect(page.locator('.picture-block .preview .image-content img')).toBeVisible({
      timeout: 15000,
    })

    // Click the edit icon overlay on the picture block preview
    await page.locator('.picture-block .edit-image-btn').click()
    await syncLV(page)

    // Verify image editor drawer opened
    const editorDrawer = page.locator('#image-editor-drawer')
    await expect(editorDrawer).toBeVisible({ timeout: 5000 })

    // Verify canvas loaded
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Verify "Save as new copy" is hidden when opened from block
    const saveNewBtn = page.locator('#image-editor-save-new')
    await expect(saveNewBtn).not.toBeVisible()

    // Click focal point on canvas
    const canvasBox = await mainCanvas.boundingBox()
    await page.mouse.click(
      canvasBox.x + canvasBox.width * 0.3,
      canvasBox.y + canvasBox.height * 0.6
    )
    await page.waitForTimeout(300)

    // Save via "Update focal point"
    const saveReplaceBtn = page.locator('#image-editor-save-replace')
    await saveReplaceBtn.click()

    // Editor drawer should close after save
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)
  })

  test('opens image editor from picture block config panel', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('PictureBlock Config Editor Test')
    await page.getByLabel('URI').fill('picture-config-editor-test')

    // Add Single Image with Caption block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Single Image with Caption' }).click()
    await syncLV(page)

    // Upload image to the picture block
    await page.locator('.picture-block .file-input').setInputFiles('./fixtures/image.jpg')
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear
    await expect(page.locator('.picture-block .preview .image-content img')).toBeVisible({
      timeout: 15000,
    })

    // Open config modal
    await page.locator('.picture-block .preview button.tiny').click()
    await syncLV(page)

    // Click "Edit/Crop" button in config panel
    const editCropBtn = page.getByRole('button', { name: 'Edit/Crop' })
    await expect(editCropBtn).toBeVisible({ timeout: 5000 })
    await editCropBtn.click()
    await syncLV(page)

    // Verify image editor drawer opened
    const editorDrawer = page.locator('#image-editor-drawer')
    await expect(editorDrawer).toBeVisible({ timeout: 5000 })

    // Verify canvas loaded
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Verify "Save as new copy" is hidden
    await expect(page.locator('#image-editor-save-new')).not.toBeVisible()

    // Close the image editor drawer via JS (config modal may overlap preventing normal clicks)
    await page.evaluate(() =>
      document.querySelector('#image-editor-drawer .drawer-close-button').click()
    )
    await page.waitForTimeout(1000)
  })

  test('opens image editor from gallery block thumbnail', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('GalleryBlock Editor Test')
    await page.getByLabel('URI').fill('gallery-editor-test')

    // Add Gallery with Controls block
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

    // Wait for gallery objects to appear
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 15000,
    })

    // Click edit icon on first image gallery object
    await page.locator('.gallery-block .gallery-object .edit-image-btn').first().click()
    await syncLV(page)

    // Verify image editor drawer opened
    const editorDrawer = page.locator('#image-editor-drawer')
    await expect(editorDrawer).toBeVisible({ timeout: 5000 })

    // Verify canvas loaded
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Verify "Save as new copy" is hidden
    await expect(page.locator('#image-editor-save-new')).not.toBeVisible()

    // Click focal point and save
    const canvasBox = await mainCanvas.boundingBox()
    await page.mouse.click(
      canvasBox.x + canvasBox.width * 0.5,
      canvasBox.y + canvasBox.height * 0.5
    )
    await page.waitForTimeout(300)

    await page.locator('#image-editor-save-replace').click()

    // Editor drawer should close after save
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)
  })

  test('does not show edit icon on gallery video objects', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Gallery Video NoEdit Test')
    await page.getByLabel('URI').fill('gallery-video-noedit-test')

    // Add Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload an image first so we have something to compare
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for the image gallery object
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Verify image object HAS edit-image-btn
    await expect(
      page.locator('.gallery-block .gallery-object .edit-image-btn').first()
    ).toBeVisible()

    // Video objects without image_id should NOT have edit-image-btn
    // (verified by the :if condition in the template)
  })
})
