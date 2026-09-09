import { test, expect } from '../../test-support/setupAuth'
import { syncLV, dragAndDrop, fillSlugSource, confirmUploadFolder } from '../../utils'

test('creates project', async ({ page }) => {
  test.setTimeout(120000)

  await page.goto('/admin')
  await page.getByRole('link', { name: 'Clients' }).click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await page.getByText('Published').click()
  await page.getByRole('textbox', { name: 'Name' }).click()
  await page.getByRole('textbox', { name: 'Name' }).fill('Microsoft')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Categories', exact: true }).click()
  await expect(page).toHaveURL(/\/categories/)
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Title' }).click()
  await page.getByRole('textbox', { name: 'Title' }).fill('Design')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await page.getByRole('textbox', { name: 'Title' }).click()
  await page.getByRole('textbox', { name: 'Title' }).fill('Strategy')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Projects' }).click()
  await expect(page).toHaveURL(/\/projects\/projects/)
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)

  await page.locator('label').filter({ hasText: 'Published' }).click()
  const titleField = page.getByRole('textbox', { name: 'Title' })
  await fillSlugSource(titleField, 'Microsoft')
  await syncLV(page)
  // Wait for slug field to be populated
  await expect(page.locator('input[name="project[slug]"]')).toHaveValue(/microsoft/, { timeout: 10000 })
  await page.getByText('Published', { exact: true }).click()
  await page.locator('#project_full_case-field-base div').click()

  // Use pressSequentially instead of fill() for TipTap contenteditable elements
  // fill() doesn't reliably trigger TipTap's input handlers
  const editor = page.locator('.tiptap-wrapper [contenteditable="true"]').first()

  await expect(editor).toBeVisible()
  await expect(editor).toBeEnabled()
  await editor.click() // Focus the editor
  await editor.pressSequentially('Hello from Playwright!', { delay: 10 })

  // Wait for TipTap to process input, then blur to trigger sync with hidden input
  await page.waitForTimeout(100)
  await editor.evaluate(el => el.blur())
  await page.waitForTimeout(200)

  const editorContent = await editor.innerText()
  expect(editorContent).toBe('Hello from Playwright!')

  // check the input value of `input[name="project[introduction]"]`
  const introductionInput = page.locator('input[name="project[introduction]"]')
  const introductionInputValue = await introductionInput.inputValue()
  expect(introductionInputValue).toBe('<p>Hello from Playwright!</p>')

  await syncLV(page)

  await page
    .locator('#project_project_categories-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: 'Design' }).click()
  await page.getByRole('button', { name: 'Strategy' }).click()
  await page.getByRole('button', { name: 'OK' }).click()
  await page
    .locator('#project_client_id-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: 'Microsoft' }).click()

  // Upload and replace the listing image in its field, leaving both assets
  // available for the compatible-library selection checks below.
  const listingImage = page.locator('#project_listing_image-media')
  await listingImage.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(listingImage.locator('img')).toBeVisible({ timeout: 30000 })
  const firstImageId = await listingImage.getAttribute('data-asset-id')
  await listingImage.locator('input[type="file"]').setInputFiles('./fixtures/image2.jpg')
  await confirmUploadFolder(page)
  await expect(listingImage).not.toHaveAttribute('data-asset-id', firstImageId, { timeout: 30000 })
  await expect(listingImage.locator('img')).toBeVisible({ timeout: 30000 })
  const secondImageId = await listingImage.getAttribute('data-asset-id')

  const galleryFileChooser = page.waitForEvent('filechooser')
  await page.locator('.gallery-input').getByRole('button', { name: 'Upload media' }).click()
  await (await galleryFileChooser).setFiles(['./fixtures/image2.jpg', './fixtures/image.jpg'])
  await confirmUploadFolder(page)

  // Wait for progress bars to complete (image uploads can take a while)
  await expect(page.locator('progress')).toHaveCount(0, { timeout: 15000 })

  // Wait for both gallery images to be visible
  const firstGalleryObjectImg = page
    .locator('[id$="-sortable-gallery-objects"] .gallery-object img')
    .first()
  const secondGalleryObjectImg = page
    .locator('[id$="-sortable-gallery-objects"] .gallery-object img')
    .nth(1)

  await expect(firstGalleryObjectImg).toBeVisible()
  await expect(secondGalleryObjectImg).toBeVisible()

  // Wait for images to be fully persisted to the database
  await syncLV(page)
  // Additional wait to ensure async DB operations complete
  await page.waitForTimeout(300)
  await syncLV(page)

  const firstGalleryObjectImgSrc = await firstGalleryObjectImg.getAttribute('src')
  const secondGalleryObjectImgSrc = await secondGalleryObjectImg.getAttribute('src')

  // Just verify both images are visible and have different sources
  // (exact filenames can vary due to collision handling)
  expect(firstGalleryObjectImgSrc).toBeTruthy()
  expect(secondGalleryObjectImgSrc).toBeTruthy()
  expect(firstGalleryObjectImgSrc).not.toBe(secondGalleryObjectImgSrc)

  // Select video for gallery
  await page.getByRole('button', { name: 'Select videos' }).click()
  await syncLV(page)

  const videoPicker = page.locator('#video-picker')
  await expect(videoPicker).toBeVisible()

  // This gallery has its own video config target, so its library starts empty.
  // Create a compatible direct video in that context; creation selects it and
  // adds it to the gallery through the same picker event contract.
  await videoPicker.getByRole('button', { name: 'Add from URL' }).click()
  await videoPicker
    .getByPlaceholder('Paste YouTube, Vimeo or direct video URL')
    .fill('https://example.com/project-gallery-video.mp4')
  await videoPicker.getByRole('button', { name: 'Create video' }).click()
  await syncLV(page)

  // Close the video picker drawer
  await videoPicker.getByRole('button', { name: 'Close' }).click()
  await page.waitForSelector('#video-picker', { state: 'hidden' })

  // Verify video appears in gallery grid (2 images + 1 video)
  const galleryObjects = page.locator('[id$="-sortable-gallery-objects"] .gallery-object')
  await expect(galleryObjects).toHaveCount(3)

  const firstGalleryObjectHandle = page
    .locator('[id$="-sortable-gallery-objects"] .gallery-object')
    .first()

  const secondGalleryObjectHandle = page
    .locator('[id$="-sortable-gallery-objects"] .gallery-object')
    .nth(1)

  // await firstGalleryObjectHandle.hover()
  // await page.mouse.down()
  // await secondGalleryObjectHandle.hover()
  // await page.waitForTimeout(300)
  // await page.mouse.up()

  const boundingBox = await firstGalleryObjectHandle.boundingBox()
  await dragAndDrop(page, firstGalleryObjectHandle, firstGalleryObjectHandle, {
    x: boundingBox.x + 250,
    y: boundingBox.y + 50,
  })

  await page.waitForTimeout(200)
  await syncLV(page)

  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading', exact: true }).click()

  await syncLV(page)

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await expect(page.locator('.content-list .list-row').nth(0)).toContainText('Microsoft')

  // Reopen the project — the gallery objects (2 images + 1 video) must have
  // PERSISTED through the save, not just rendered in the editor.
  await page
    .locator('.content-list .list-row')
    .nth(0)
    .getByRole('link', { name: 'Microsoft' })
    .click()
  await syncLV(page)
  await expect(page.locator('[id$="-sortable-gallery-objects"] .gallery-object')).toHaveCount(3, {
    timeout: 20000,
  })

  // The listing image must also have persisted (image entry_field delivery).
  await expect(listingImage).toHaveAttribute('data-asset-id', secondImageId, { timeout: 20000 })

  // The picker selection follows the current unsaved drawer preview. It must
  // not fall back to whichever image was persisted when the drawer opened.
  await listingImage.getByRole('button', { name: 'Configure', exact: true }).click()
  const imageDrawer = page.locator('#image-drawer')
  await imageDrawer.getByRole('button', { name: 'Replace', exact: true }).click()
  await imageDrawer.getByRole('button', { name: 'Browse library', exact: true }).click()
  await syncLV(page)

  const imagePicker = page.locator('#image-picker')
  await expect(imagePicker).toBeVisible()
  const initiallySelectedImage = imagePicker.locator('.image-picker__image.selected')
  await expect(initiallySelectedImage).toHaveCount(1)
  const initiallySelectedId = await initiallySelectedImage.getAttribute('data-id')

  const replacementImages = imagePicker.locator('.image-picker__image:not(.selected)')
  await expect(replacementImages.first()).toBeVisible()
  const replacementId = await replacementImages.first().getAttribute('data-id')
  await replacementImages.first().click()
  await page.waitForSelector('#image-picker', { state: 'hidden' })
  await expect(imageDrawer.locator('img')).toBeVisible()

  await imageDrawer.getByRole('button', { name: 'Replace', exact: true }).click()
  await imageDrawer.getByRole('button', { name: 'Browse library', exact: true }).click()
  await syncLV(page)

  await expect(imagePicker.locator(`.image-picker__image[data-id="${replacementId}"]`)).toHaveClass(
    /selected/
  )
  await expect(
    imagePicker.locator(`.image-picker__image[data-id="${initiallySelectedId}"]`)
  ).not.toHaveClass(/selected/)

  await imagePicker.getByRole('button', { name: 'Close' }).click()
  await page.waitForSelector('#image-picker', { state: 'hidden' })
  await imageDrawer.getByRole('button', { name: 'Done', exact: true }).click()
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await syncLV(page)

  // The gallery's shared input accepts a local video as well as images.
  await page
    .locator('.gallery-input input[type="file"]')
    .setInputFiles('./fixtures/video.mp4')
  await syncLV(page)
  await expect(page.locator('[id$="-sortable-gallery-objects"] .gallery-object')).toHaveCount(4, {
    timeout: 20000,
  })

  // Save + reopen — the uploaded gallery video must persist as a video_id
  // gallery object.
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await syncLV(page)
  await page
    .locator('.content-list .list-row')
    .nth(0)
    .getByRole('link', { name: 'Microsoft' })
    .click()
  await syncLV(page)
  await expect(page.locator('[id$="-sortable-gallery-objects"] .gallery-object')).toHaveCount(4, {
    timeout: 20000,
  })

  // Upload a local video directly to the cover field.
  const coverVideo = page.locator('#project_cover_video-media')
  await coverVideo.locator('input[type="file"]').setInputFiles('./fixtures/video.mp4')
  await expect(coverVideo).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
  const videoId = await coverVideo.getAttribute('data-asset-id')

  // Save + reopen — the video field must persist.
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await syncLV(page)
  await page
    .locator('.content-list .list-row')
    .nth(0)
    .getByRole('link', { name: 'Microsoft' })
    .click()
  await syncLV(page)
  await expect(coverVideo).toHaveAttribute('data-asset-id', videoId, { timeout: 20000 })
  await expect(page.locator('[id$="-sortable-gallery-objects"] .gallery-object')).toHaveCount(4, {
    timeout: 20000,
  })

  // Upload the cover file through the same field intake.
  const coverFile = page.locator('#project_cover_file-media')
  await coverFile.locator('input[type="file"]').setInputFiles('./fixtures/test.pdf')
  await expect(coverFile).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
  const fileId = await coverFile.getAttribute('data-asset-id')

  // Save + reopen — EVERY entry-field asset must persist together: file,
  // video, listing image and the 4 gallery objects.
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await syncLV(page)
  await page
    .locator('.content-list .list-row')
    .nth(0)
    .getByRole('link', { name: 'Microsoft' })
    .click()
  await syncLV(page)
  await expect(coverFile).toHaveAttribute('data-asset-id', fileId, { timeout: 20000 })
  await expect(coverVideo).toHaveAttribute('data-asset-id', videoId)
  await expect(listingImage).toHaveAttribute('data-asset-id', replacementId)
  await expect(page.locator('[id$="-sortable-gallery-objects"] .gallery-object')).toHaveCount(4, {
    timeout: 20000,
  })
})
