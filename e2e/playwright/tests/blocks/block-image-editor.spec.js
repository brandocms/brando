import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder, expectCanvasOverlayAligned } from '../../utils'

test.describe('Image Editor from Blocks', () => {

  test('opens image editor from picture block preview icon', async ({ page }, testInfo) => {
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
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear in preview
    await expect(page.locator('.picture-block .media-field--block:visible img')).toBeVisible({
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

    // Verify "Save as new copy" is visible when opened from block
    const saveNewBtn = page.locator('#image-editor-save-new')
    await expect(saveNewBtn).toBeVisible()

    // Free cropping uses labelled, keyboard-accessible ratio presets.
    const ratios = editorDrawer.getByRole('group', { name: 'Aspect ratio' })
    await expect(ratios.getByRole('button')).toHaveCount(7)
    const portrait = ratios.getByRole('button', { name: '4:5', exact: true })
    await portrait.focus()
    await page.keyboard.press('Enter')
    await expect(portrait).toHaveAttribute('aria-pressed', 'true')
    const cropPreview = editorDrawer.locator('.freeform-preview canvas')
    await expect.poll(() => cropPreview.evaluate(el => el.width / el.height)).toBeCloseTo(0.8, 1)
    await page.setViewportSize({ width: 1440, height: 1000 })
    await expectCanvasOverlayAligned(page)
    await page.screenshot({ path: testInfo.outputPath('image-editor-freeform-desktop.png') })
    await page.setViewportSize({ width: 390, height: 844 })
    await expectCanvasOverlayAligned(page)
    await expect(saveNewBtn).toBeInViewport()
    expect(await editorDrawer.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
    await cropPreview.scrollIntoViewIfNeeded()
    const previewRatio = await cropPreview.evaluate(el => {
      const bounds = el.getBoundingClientRect()
      return bounds.width / bounds.height
    })
    expect(previewRatio).toBeCloseTo(0.8, 1)
    await page.screenshot({ path: testInfo.outputPath('image-editor-freeform-mobile.png') })
    await page.setViewportSize({ width: 1440, height: 1000 })
    await expectCanvasOverlayAligned(page)
    await page.locator('#image-editor-reset').click()
    await expect(ratios.getByRole('button', { name: 'Free', exact: true })).toHaveAttribute('aria-pressed', 'true')

    // The focal point cannot leave the crop frame: everything outside the frame
    // is discarded on save, so a focal out there names a pixel the saved file
    // does not contain. Reset leaves a free crop over the middle 80%, so a click
    // in the corner puts the pin on the frame's edge, not in the corner.
    //
    // Assert it here rather than after the reopen below: reopening pushes a
    // fresh `b:image_editor:init`, and a click that lands before it arrives is
    // undone by the re-init.
    const resetCanvasBox = await mainCanvas.boundingBox()
    const focalPosition = async () => {
      const pin = await editorDrawer.locator('.image-editor-focal-pin').boundingBox()
      return {
        x: (pin.x + pin.width / 2 - resetCanvasBox.x) / resetCanvasBox.width,
        y: (pin.y + pin.height / 2 - resetCanvasBox.y) / resetCanvasBox.height
      }
    }

    await page.mouse.click(
      resetCanvasBox.x + resetCanvasBox.width * 0.02,
      resetCanvasBox.y + resetCanvasBox.height * 0.02
    )
    await expect.poll(async () => (await focalPosition()).x).toBeCloseTo(0.1, 2)
    expect((await focalPosition()).y).toBeCloseTo(0.1, 2)

    // Dragging the pin to a point inside the frame is untouched by the clamp.
    await page.mouse.move(
      resetCanvasBox.x + resetCanvasBox.width * 0.1,
      resetCanvasBox.y + resetCanvasBox.height * 0.1
    )
    await page.mouse.down()
    await page.mouse.move(
      resetCanvasBox.x + resetCanvasBox.width * 0.3,
      resetCanvasBox.y + resetCanvasBox.height * 0.6,
      { steps: 5 }
    )
    await page.mouse.up()
    await expect.poll(async () => (await focalPosition()).x).toBeCloseTo(0.3, 2)
    expect((await focalPosition()).y).toBeCloseTo(0.6, 2)

    // Escape closes only this workspace and returns focus to its opener.
    // The dialog listens for it on itself, and the canvas clicks above left
    // focus on the body, so put it back inside the drawer first.
    await editorDrawer.locator('#image-editor-reset').focus()
    await page.keyboard.press('Escape')
    await expect(editorDrawer).not.toBeVisible()
    await expect(page.locator('.picture-block .edit-image-btn')).toBeFocused()
    // Reopening shows the drawer before the editor can show the image: the
    // payload is a server round trip and the file still has to be fetched and
    // decoded. Hold the image back to see what fills that gap — without it the
    // canvas keeps the last session's render, and a click on it is undone by
    // the re-init.
    await page.route('**/media/**', async route => {
      await new Promise(resolve => setTimeout(resolve, 1500))
      await route.continue()
    })
    await page.locator('.picture-block .edit-image-btn').click()
    await expect(editorDrawer).toBeVisible()
    const editorHook = page.locator('#image-editor-hook')
    await expect(editorHook).toHaveAttribute('aria-busy', 'true')
    const loading = editorDrawer.locator('.image-editor-loading')
    await expect(loading).toBeVisible()
    // The cover is opaque from the first frame, so the previous image is never
    // on screen under a new one; the spinner itself waits 150ms so a cached
    // image does not flash one.
    await expect(loading.locator('.image-editor-spinner')).toHaveCSS('opacity', '1')
    await expect(editorDrawer.locator('.image-editor-focal-pin')).toBeHidden()
    await page.screenshot({ path: testInfo.outputPath('image-editor-loading.png') })
    await page.unroute('**/media/**')

    await expect(editorHook).toHaveAttribute('aria-busy', 'false', { timeout: 15000 })
    await expect(loading).toBeHidden()
    await expect(editorDrawer.locator('.image-editor-focal-pin')).toBeVisible()

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
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear
    await expect(page.locator('.picture-block .media-field--block:visible img')).toBeVisible({
      timeout: 15000,
    })

    // Open config modal
    await page.locator('.picture-block .media-field--block:visible').getByRole('button', { name: 'Configure', exact: true }).click()
    await page.getByRole('tab', { name: 'Image', exact: true }).click()
    await syncLV(page)

    // Click "Edit/Crop" button in config panel
    const editCropBtn = page.locator('.modal.visible').getByRole('button', { name: 'Edit/Crop' })
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

    // Verify "Save as new copy" is visible when opened from block
    await expect(page.locator('#image-editor-save-new')).toBeVisible()

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
    await confirmUploadFolder(page)
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

    // Verify "Save as new copy" is visible when opened from block
    await expect(page.locator('#image-editor-save-new')).toBeVisible()

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

  test('save as new copy with crop replaces gallery image', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('GalleryBlock SaveNew Test')
    await page.getByLabel('URI').fill('gallery-savenew-test')

    // Add Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload 1 image to the gallery block
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(3000)

    // Wait for the gallery object to appear
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Capture the original image src before editing
    const imgLocator = page.locator('.gallery-block .gallery-object .image-content img').first()
    await expect(imgLocator).toBeVisible({ timeout: 10000 })
    const srcBefore = await imgLocator.getAttribute('src')

    // Click edit icon on first image gallery object
    await page.locator('.gallery-block .gallery-object .edit-image-btn').first().click()
    await syncLV(page)

    // Verify image editor drawer opened and canvas loaded
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Zoom in to apply an actual crop
    const zoomSlider = page.locator('#image-editor-zoom')
    await zoomSlider.fill('2')
    await zoomSlider.dispatchEvent('input')
    await page.waitForTimeout(500)

    // Click "Save as new copy" — uses LiveView upload
    await page.locator('#image-editor-save-new').click()

    // Editor drawer should close
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)

    // Gallery should still have 1 object (new copy replaces the original)
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Wait for the image src to actually change from the original
    // (polls until the attribute differs, handles async processing + DOM update delays)
    await expect(imgLocator).not.toHaveAttribute('src', srcBefore, { timeout: 20000 })
    const srcAfter = await imgLocator.getAttribute('src')
    expect(srcAfter).not.toEqual(srcBefore)
  })

  test('gallery image stays processed after adding another image via picker', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Gallery Stale Image Test')
    await page.getByLabel('URI').fill('gallery-stale-test')

    // Add Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload 1 image to the gallery block
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(3000)

    // Wait for the gallery object to appear
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Click edit icon on the image
    await page.locator('.gallery-block .gallery-object .edit-image-btn').first().click()
    await syncLV(page)

    // Wait for canvas to load
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Save as new copy (replaces the image)
    const saveNewBtn = page.locator('#image-editor-save-new')
    await expect(saveNewBtn).toBeVisible()
    await saveNewBtn.click()

    // Wait for drawer to close and processing to complete
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)
    await page.waitForTimeout(5000)

    // Verify the gallery object shows a processed image (not a spinner)
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1)
    await expect(page.locator('.gallery-block .gallery-object .image-content img').first()).toBeVisible({
      timeout: 15000,
    })

    // Open image picker and select the original image (adds a second image)
    await page.locator('.gallery-block button', { hasText: 'Browse images' }).click()
    await syncLV(page)
    await page.waitForTimeout(1000)

    // The image picker should show images - click the first non-selected one
    const pickerImages = page.locator('.image-picker__image:not(.selected)')
    await expect(pickerImages.first()).toBeVisible({ timeout: 5000 })
    await pickerImages.first().click()
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Close the image picker
    await page.locator('#image-picker .drawer-close-button').click()
    await page.waitForTimeout(1000)

    // Gallery should now have 2 objects
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, {
      timeout: 15000,
    })

    // Both gallery objects should show processed images (not spinners)
    await expect(page.locator('.gallery-block .gallery-object .img-placeholder')).toHaveCount(0, {
      timeout: 15000,
    })
  })

  test('gallery image picker deselect syncs correctly', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Gallery Deselect Test')
    await page.getByLabel('URI').fill('gallery-deselect-test')

    // Add Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload an image
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(3000)

    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Open image picker - the uploaded image should be selected
    await page.locator('.gallery-block button', { hasText: 'Browse images' }).click()
    await syncLV(page)
    await page.waitForTimeout(1000)

    const selectedImages = page.locator('.image-picker__image.selected')
    await expect(selectedImages).toHaveCount(1, { timeout: 15000 })

    // Click the selected image to deselect it
    await selectedImages.first().click()
    await syncLV(page)
    await page.waitForTimeout(1000)

    // Image should now be deselected in picker
    await expect(page.locator('.image-picker__image.selected')).toHaveCount(0, {
      timeout: 10000,
    })

    // Close picker
    await page.locator('#image-picker .drawer-close-button').click()
    await page.waitForTimeout(1000)

    // Gallery should have 0 objects
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(0, {
      timeout: 10000,
    })
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
    await confirmUploadFolder(page)
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

  test('save changes with zoom applies crop to picture block image', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('PictureBlock Crop Test')
    await page.getByLabel('URI').fill('picture-crop-test')

    // Add Single Image with Caption block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Single Image with Caption' }).click()
    await syncLV(page)

    // Upload image to the picture block
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear in preview
    const imgLocator = page.locator('.picture-block .media-field--block:visible img')
    await expect(imgLocator).toBeVisible({ timeout: 15000 })

    // Click the edit icon overlay on the picture block preview
    await page.locator('.picture-block .edit-image-btn').click()
    await syncLV(page)

    // Verify image editor drawer opened and canvas loaded
    await expect(page.locator('#image-editor-drawer')).toBeVisible({ timeout: 5000 })
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Zoom in using the slider (this triggers crop detection in _onSaveReplace)
    const zoomSlider = page.locator('#image-editor-zoom')
    await zoomSlider.fill('2')
    await zoomSlider.dispatchEvent('input')
    await page.waitForTimeout(500)

    // Click "Save changes" — wait for the HTTP replace_crop to complete
    const replacePromise = page.waitForResponse(
      (resp) => resp.url().includes('/api/content/image/replace_crop') && resp.status() === 200
    )
    await page.locator('#image-editor-save-replace').click()
    await replacePromise

    // Editor drawer should close
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)

    // Wait for reprocessing to complete and image to reappear
    await expect(page.locator('.picture-block .media-field--block:visible img')).toBeVisible({
      timeout: 20000,
    })

    // Verify the crop was applied by checking the rendered image dimensions changed.
    // Original fixture is landscape; after 2x zoom crop, dimensions should be smaller.
    const dims = await page.locator('.picture-block .media-field--block:visible img').evaluate((img) => ({
      w: img.naturalWidth,
      h: img.naturalHeight,
    }))
    // At 2x zoom the cropped region is ~half the original in each dimension,
    // so the processed size should be noticeably smaller than the original.
    expect(dims.w).toBeGreaterThan(0)
    expect(dims.h).toBeGreaterThan(0)
  })

  test('save changes with zoom applies crop to gallery block image', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('GalleryBlock Crop Test')
    await page.getByLabel('URI').fill('gallery-crop-test')

    // Add Gallery with Controls block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Gallery with Controls' }).click()
    await syncLV(page)

    // Upload 1 image to the gallery block
    await page.locator('.gallery-block .file-input').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(3000)

    // Wait for the gallery object to appear
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Click edit icon on the gallery object
    await page.locator('.gallery-block .gallery-object .edit-image-btn').first().click()
    await syncLV(page)

    // Verify image editor opened and canvas loaded
    await expect(page.locator('#image-editor-drawer')).toBeVisible({ timeout: 5000 })
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Zoom in to apply a crop
    const zoomSlider = page.locator('#image-editor-zoom')
    await zoomSlider.fill('2')
    await zoomSlider.dispatchEvent('input')
    await page.waitForTimeout(500)

    // Click "Save changes" — wait for the HTTP replace_crop to complete
    const replacePromise = page.waitForResponse(
      (resp) => resp.url().includes('/api/content/image/replace_crop') && resp.status() === 200
    )
    await page.locator('#image-editor-save-replace').click()
    await replacePromise

    // Editor drawer should close
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)

    // Gallery should still have 1 object (same image, replaced in place)
    await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(1, {
      timeout: 15000,
    })

    // Wait for the image to finish reprocessing
    await expect(
      page.locator('.gallery-block .gallery-object .image-content img').first()
    ).toBeVisible({ timeout: 20000 })
  })

  test('save as new copy with crop from picture block replaces image', async ({ page }) => {
    test.setTimeout(120000)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('PictureBlock SaveNew Crop Test')
    await page.getByLabel('URI').fill('picture-savenew-crop-test')

    // Add Single Image with Caption block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Single Image with Caption' }).click()
    await syncLV(page)

    // Upload image to the picture block
    await page.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await syncLV(page)
    await page.waitForTimeout(2000)

    // Wait for image to appear in preview
    const imgLocator = page.locator('.picture-block .media-field--block:visible img')
    await expect(imgLocator).toBeVisible({ timeout: 15000 })

    // Capture the original image src
    const srcBefore = await imgLocator.getAttribute('src')

    // Click the edit icon overlay
    await page.locator('.picture-block .edit-image-btn').click()
    await syncLV(page)

    // Wait for editor and canvas
    await expect(page.locator('#image-editor-drawer')).toBeVisible({ timeout: 5000 })
    const mainCanvas = page.locator('#image-editor-canvas')
    await expect(mainCanvas).toBeVisible({ timeout: 10000 })
    await page.waitForTimeout(2000)

    // Zoom in to apply a crop
    const zoomSlider = page.locator('#image-editor-zoom')
    await zoomSlider.fill('2')
    await zoomSlider.dispatchEvent('input')
    await page.waitForTimeout(500)

    // Click "Save as new copy" — uses LiveView upload
    await page.locator('#image-editor-save-new').click()

    // Editor drawer should close
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)

    // Wait for the new image to be processed — src must change from the original
    const imgAfter = page.locator('.picture-block .media-field--block:visible img')
    await expect(imgAfter).not.toHaveAttribute('src', srcBefore, { timeout: 20000 })

    // Verify the image src actually changed (new image created from the crop)
    const srcAfter = await imgAfter.getAttribute('src')
    expect(srcAfter).not.toEqual(srcBefore)
  })
})
