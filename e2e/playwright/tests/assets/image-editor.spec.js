import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  fillSlugSource,
  confirmUploadFolder,
  expectCanvasOverlayAligned,
} from '../../utils'

test('opens image editor, adjusts focal point, and saves', async ({ page }, testInfo) => {
  test.setTimeout(120000)

  // Step 1: Navigate to projects and create a client first
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Clients' }).click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await page.getByText('Published').click()
  await fillSlugSource(page.getByRole('textbox', { name: 'Name' }), 'ImgEdClient')
  await syncLV(page)
  await expect(page.locator('input[name="client[slug]"]')).toHaveValue('imgedclient', { timeout: 10000 })
  await page.getByTestId('submit').click()
  await syncLV(page)

  // Step 2: Create a new project
  await page.getByRole('link', { name: 'Projects' }).click()
  await expect(page).toHaveURL(/\/projects\/projects/)
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)

  // Fill required fields
  await page.locator('label').filter({ hasText: 'Published' }).click()
  const titleField = page.getByRole('textbox', { name: 'Title' })
  await fillSlugSource(titleField, 'ImgEditorTest')
  await syncLV(page)
  await expect(page.locator('input[name="project[slug]"]')).toHaveValue(/imgeditortest/, {
    timeout: 10000,
  })

  // Fill introduction (required field)
  const tiptapEditor = page.locator('.tiptap-wrapper [contenteditable="true"]').first()
  await expect(tiptapEditor).toBeVisible()
  await tiptapEditor.click()
  await tiptapEditor.pressSequentially('Test introduction', { delay: 10 })
  await page.waitForTimeout(100)
  await tiptapEditor.evaluate((el) => el.blur())
  await page.waitForTimeout(200)
  await syncLV(page)

  // Select client (required field) and wait for it to register
  await page
    .locator('#project_client_id-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await syncLV(page)
  await page.getByRole('button', { name: 'ImgEdClient' }).click()
  await syncLV(page)

  // Upload through the field, then edit shared metadata in the workspace drawer.
  const imageField = page.locator('#project_listing_image-media')
  await imageField.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(imageField.locator('img')).toBeVisible({ timeout: 30000 })
  await imageField.getByRole('button', { name: 'Configure', exact: true }).click()
  const details = page.getByRole('dialog', { name: 'Image details', exact: true })
  // Alt text is per language: the first tab's input is the one shown.
  const altField = details.locator('.i18n-field:has(input[name*="[alt]["])')
  const altInput = altField.locator('.i18n-panel.is-active input')
  const altTab = altField.locator('.i18n-tab.is-active')
  await expect(altTab).toHaveAttribute('data-empty', 'true')
  await altInput.fill('Library description')
  await syncLV(page)
  await expect(altTab).toHaveAttribute('data-empty', 'false')
  await details.getByRole('button', { name: 'Replace', exact: true }).click()
  await details.getByRole('button', { name: 'Select image', exact: true }).click()
  const browser = page.getByRole('dialog', { name: 'Images', exact: true })
  await expect(browser).toBeVisible()
  // The drawer becomes visible before its hook moves keyboard focus into it.
  // Escape belongs to the nested picker only after that handoff completes.
  await expect.poll(() => browser.evaluate(el => el.contains(document.activeElement))).toBe(true)
  await page.keyboard.press('Escape')
  await expect(browser).not.toBeVisible()
  await expect(details).toBeVisible()
  // The menu closes on selection, so focus returns to its visible disclosure.
  await expect(details.getByRole('button', { name: 'Replace', exact: true })).toBeFocused()
  await expect(altInput).toHaveValue('Library description')
  await page.screenshot({ path: testInfo.outputPath('image-details-desktop.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(details.getByRole('button', { name: 'Done', exact: true })).toBeInViewport()
  expect(await details.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await page.screenshot({ path: testInfo.outputPath('image-details-mobile.png') })
  await details.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(details).not.toBeVisible()
  await page.setViewportSize({ width: 1440, height: 1000 })
  await syncLV(page)

  // Step 4: Save the project so the image is fully persisted and processed
  await page.getByTestId('submit').click()
  await syncLV(page, 30000)

  // Verify we're back on the listing page
  await expect(page).toHaveURL(/\/admin\/projects\/projects/, { timeout: 30000 })
  await expect(page.locator('.content-list .list-row').first()).toContainText('ImgEditorTest')

  // Step 5: Navigate back to edit the project
  await page.locator('.content-list .list-row').first().locator('.circle-dropdown').click()
  await page.getByRole('button', { name: /Edit/ }).click()
  await syncLV(page)

  // Step 6: Open the image drawer by clicking "Edit image" on the listing image
  await imageField.getByRole('button', { name: 'Configure', exact: true }).click()
  await syncLV(page)

  // Verify the image drawer is open and image is visible
  await expect(page.locator('#image-drawer img')).toBeVisible({ timeout: 10000 })

  // Step 7: Click "Edit/Crop image" button in the image drawer
  const editCropBtn = details.getByRole('button', { name: 'Edit/Crop', exact: true })
  await expect(editCropBtn).toBeVisible({ timeout: 10000 })
  await editCropBtn.click()
  await syncLV(page)

  // Step 8: Verify the image editor drawer opened
  const editorDrawer = page.locator('#image-editor-drawer')
  await expect(editorDrawer).toBeVisible({ timeout: 5000 })

  // Verify the main canvas is present and wait for image to load
  const mainCanvas = page.locator('#image-editor-canvas')
  await expect(mainCanvas).toBeVisible({ timeout: 10000 })
  await page.waitForTimeout(2000)

  // Step 9: Verify key UI elements
  const focalPin = editorDrawer.locator('.image-editor-focal-pin')
  await expect(focalPin).toBeVisible()

  const zoomSlider = page.locator('#image-editor-zoom')
  await expect(zoomSlider).toBeVisible()
  const zoomValue = page.locator('#image-editor-zoom-value')
  await expect(zoomValue).toContainText('1.00x')

  // Verify crop previews are rendered (listing_image has a 3:2 crop via xlarge_crop)
  const previewsContainer = page.locator('#image-editor-previews')
  await expect(previewsContainer).toBeVisible()
  const previewCanvases = previewsContainer.locator('canvas')
  await expect(previewCanvases).toHaveCount(1, { timeout: 5000 })
  await expect(editorDrawer).toHaveAttribute('role', 'dialog')
  await expect(previewsContainer.locator('.crop-preview-ratio')).toHaveText('3:2')
  await expect(previewsContainer.locator('.crop-preview-sizes')).toContainText('xlarge_crop')
  await expect(editorDrawer.locator('.freeform-ratios')).toHaveCount(0)
  await expect(page.locator('#image-editor-save-new')).toBeInViewport()
  await expectCanvasOverlayAligned(page)
  await page.screenshot({ path: testInfo.outputPath('image-editor-configured-desktop.png') })

  await page.setViewportSize({ width: 390, height: 844 })
  await expectCanvasOverlayAligned(page)
  await expect(page.locator('#image-editor-save-new')).toBeInViewport()
  expect(await editorDrawer.evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await zoomSlider.scrollIntoViewIfNeeded()
  await expect(zoomSlider).toBeInViewport()
  await previewCanvases.first().scrollIntoViewIfNeeded()
  await expect(previewCanvases.first()).toBeInViewport()
  const cropPreviewRatio = await previewCanvases.first().evaluate(el => {
    const bounds = el.getBoundingClientRect()
    return bounds.width / bounds.height
  })
  expect(cropPreviewRatio).toBeCloseTo(1.5, 1)
  await page.screenshot({ path: testInfo.outputPath('image-editor-configured-mobile.png') })
  await page.setViewportSize({ width: 1440, height: 1000 })
  await expectCanvasOverlayAligned(page)
  await mainCanvas.scrollIntoViewIfNeeded()

  // Step 10: Interact with the focal point — click on the canvas
  const canvasBox = await mainCanvas.boundingBox()
  await page.mouse.click(
    canvasBox.x + canvasBox.width * 0.25,
    canvasBox.y + canvasBox.height * 0.75
  )
  await page.waitForTimeout(300)

  // Dragging the frame moves the focal by as much as the frame can follow, not
  // by as much as the pointer moved. The frame is centred on the focal and then
  // clamped to the image, so once it is against an edge the focal used to carry
  // on alone: the drag came loose from the pointer and left the focal somewhere
  // nobody pointed at.
  const focalPosition = async () => {
    const pin = await editorDrawer.locator('.image-editor-focal-pin').boundingBox()
    return {
      x: (pin.x + pin.width / 2 - canvasBox.x) / canvasBox.width,
      y: (pin.y + pin.height / 2 - canvasBox.y) / canvasBox.height
    }
  }

  const dragFrame = async (toX, toY) => {
    await page.mouse.move(canvasBox.x + canvasBox.width / 2, canvasBox.y + canvasBox.height / 2)
    await page.mouse.down()
    await page.mouse.move(canvasBox.x + canvasBox.width * toX, canvasBox.y + canvasBox.height * toY, { steps: 5 })
    await page.mouse.up()
    return focalPosition()
  }

  // This crop is 3:2 on a wider image, so at 1.00x it is as tall as the image
  // and has nowhere to go vertically. A drag straight down must leave the focal
  // exactly where it was.
  const start = await focalPosition()
  const draggedDown = await dragFrame(0.5, 2)
  expect(draggedDown.y).toBeCloseTo(start.y, 2)
  expect(draggedDown.x).toBeCloseTo(start.x, 2)

  // Sideways it has a little room, so the focal follows the frame into the edge
  // and stops there — nowhere near the pointer, which left the canvas entirely.
  const draggedRight = await dragFrame(2, 0.5)
  expect(draggedRight.x).toBeGreaterThan(start.x)
  expect(draggedRight.x).toBeLessThan(start.x + 0.15)
  expect(draggedRight.y).toBeCloseTo(start.y, 2)

  // Step 11: Test zoom slider
  await zoomSlider.fill('1.5')
  await zoomSlider.dispatchEvent('input')
  await page.waitForTimeout(300)
  await expect(zoomValue).toContainText('1.50x')

  // Step 12: Test reset button
  const resetBtn = page.locator('#image-editor-reset')
  await resetBtn.click()
  await page.waitForTimeout(300)
  await expect(zoomValue).toContainText('1.00x')

  // Step 13: Zoom to 1.5 and save with crop via "Save changes"
  await zoomSlider.fill('1.5')
  await zoomSlider.dispatchEvent('input')
  await page.waitForTimeout(300)
  await expect(zoomValue).toContainText('1.50x')

  const saveReplaceBtn = page.locator('#image-editor-save-replace')
  await saveReplaceBtn.click()

  // Editor drawer should auto-close after save
  await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
  await page.waitForTimeout(3000)
  await syncLV(page, 30000)

  // Close the image drawer
  await details.getByRole('button', { name: 'Done', exact: true }).click()
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await syncLV(page)

  // Verify the image dimensions changed after crop (original was 292x173)
  const dims = imageField.locator('.media-field-meta')
  await expect(dims).toBeVisible({ timeout: 10000 })
  const dimsText = await dims.textContent()
  expect(dimsText).not.toBe('292 × 173')

  // Step 14: Save the project again so the cropped image is persisted
  await page.getByTestId('submit').click()
  await syncLV(page, 30000)
  await expect(page).toHaveURL(/\/admin\/projects\/projects/, { timeout: 30000 })

  // Step 15: Navigate back to edit the project again
  await page.locator('.content-list .list-row').first().locator('.circle-dropdown').click()
  await page.getByRole('button', { name: /Edit/ }).click()
  await syncLV(page)

  // Step 16: Open the image drawer and image editor again
  await imageField.getByRole('button', { name: 'Configure', exact: true }).click()
  await syncLV(page)
  await expect(page.locator('#image-drawer img')).toBeVisible({ timeout: 10000 })

  const editCropBtn2 = details.getByRole('button', { name: 'Edit/Crop', exact: true })
  await expect(editCropBtn2).toBeVisible({ timeout: 10000 })
  await editCropBtn2.click()
  await syncLV(page)

  // Step 17: Verify the image editor opens and works for the second time
  await expect(page.locator('#image-editor-drawer')).toBeVisible({ timeout: 5000 })
  await expect(page.locator('#image-editor-canvas')).toBeVisible({ timeout: 10000 })
  await page.waitForTimeout(2000)

  // Step 18: Zoom and save again to verify "Save changes" works on re-edit
  const zoomSlider2 = page.locator('#image-editor-zoom')
  await zoomSlider2.fill('1.3')
  await zoomSlider2.dispatchEvent('input')
  await page.waitForTimeout(300)

  const saveReplaceBtn2 = page.locator('#image-editor-save-replace')
  await saveReplaceBtn2.click()

  // Editor drawer should auto-close after save
  await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
  await page.waitForTimeout(3000)
  await syncLV(page, 30000)

  // Close the image drawer
  await details.getByRole('button', { name: 'Done', exact: true }).click()
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await syncLV(page)
})
