import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A Norwegian source whose block has picture, gallery and file refs and image,
// file and gallery variables, all filled but one empty picture
// (E2EFixtureController :synchronized_translation_refs, filled=true), and its
// English synchronized translation. Media in blocks follows the source, so
// the translation shows it with a note and nothing that changes it; Configure
// stays for a use's own caption, alt text and title.

async function openFixture(page) {
  const response = await page.request.post('/e2e/synchronized-translation-refs?filled=true')
  expect(response.ok()).toBeTruthy()
  return response.json()
}

// Whether a file dragged over the element is taken: the UploadTrigger hook
// marks a drop zone that takes it with `.dragging`
async function takesDrag(locator) {
  return locator.evaluate((el) => {
    const transfer = new DataTransfer()
    transfer.items.add(new File(['x'], 'x.jpg', { type: 'image/jpeg' }))
    el.dispatchEvent(new DragEvent('dragenter', { bubbles: true, cancelable: true, dataTransfer: transfer }))
    const taken = el.classList.contains('dragging')
    el.dispatchEvent(new DragEvent('dragleave', { bubbles: true, cancelable: true, dataTransfer: transfer }))
    return taken
  })
}

test('media refs and variables show their media read-only in a synchronized translation', async ({ page }) => {
  const { target_id: targetId } = await openFixture(page)

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)

  const locked = page.locator('.blocks-wrapper.is-source-locked')
  await expect(locked).toBeVisible()

  // A chosen picture: its image and Configure, nothing to replace or remove it with
  const picture = locked.locator('[b-ref="chosen"] .block-content .media-field')
  await expect(picture.locator('.media-field-preview img')).toBeVisible()
  await expect(picture.locator('.media-source-note')).toBeVisible()
  await expect(picture.getByRole('button')).toHaveCount(1)
  await expect(picture.getByRole('button', { name: 'Configure' })).toBeVisible()
  expect(await takesDrag(picture)).toBe(false)

  // An empty picture: the empty note, no buttons, no upload folder
  const empty = locked.locator('[b-ref="photo"] .block-content .media-field')
  await expect(empty.locator('.media-source-note')).toBeVisible()
  await expect(empty.locator('button:visible')).toHaveCount(0)
  await expect(empty.locator('.media-field-destination')).toBeHidden()

  // A file: Configure only
  const file = locked.locator('[b-ref="attachment"] .block-content .media-field')
  await expect(file.locator('.media-source-note')).toBeVisible()
  await expect(file.locator('button:visible')).toHaveCount(1)
  await expect(file.getByRole('button', { name: 'Configure' })).toBeVisible()

  // A gallery: its items, each with its settings, but no upload, removal or
  // image editing, and no drop
  const gallery = locked.locator('[b-ref="slides"] .gallery-upload-wrapper')
  await expect(gallery.locator('.gallery-object')).toHaveCount(2)
  await expect(gallery.locator('.media-source-note')).toBeVisible()
  await expect(gallery.locator('.gallery-buttons')).toBeHidden()
  await expect(gallery.locator('.gallery-object .delete-x')).toHaveCount(2)
  await expect(gallery.locator('.gallery-object .delete-x:visible')).toHaveCount(0)
  await expect(gallery.locator('.gallery-object .edit-image-btn:visible')).toHaveCount(0)
  expect(await takesDrag(gallery)).toBe(false)

  // Image, file and gallery variables: the media and the note, no menu
  // (each variable's row; its settings dialog opens from the hidden menu)
  for (const type of ['image', 'file', 'gallery']) {
    const variable = locked.locator(`.block-vars .variable.${type} :is(.media-field--line, [id$="-gallery-media"])`)
    await expect(variable.locator('.media-source-note')).toBeVisible()
    await expect(variable.locator('.media-action-menu')).toBeHidden()
  }

  // The picture's settings keep its caption and alt text editable; its image
  // section shows the image and nothing to change it with
  await picture.getByRole('button', { name: 'Configure' }).click()
  const config = locked.locator('[b-ref="chosen"] .modal-sections')
  await expect(config).toBeVisible()
  await expect(config.getByRole('textbox', { name: 'Alternative text' })).toBeEditable()
  await config.getByRole('tab', { name: 'Image' }).click()
  const imagePanel = config.locator('[id$="-panel-image"]')
  await expect(imagePanel.locator('.media-field-preview img')).toBeVisible()
  await expect(imagePanel.locator('.media-source-note')).toBeVisible()
  await expect(imagePanel.locator('button:visible')).toHaveCount(0)
})

test('the source keeps every control of its media refs', async ({ page }) => {
  const { source_id: sourceId } = await openFixture(page)

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)

  const picture = page.locator('[b-ref="chosen"] .block-content .media-field')
  await expect(picture.getByRole('button', { name: 'Configure' })).toBeVisible()
  await expect(picture.getByRole('button', { name: 'Replace' })).toBeVisible()
  await expect(picture.getByRole('button', { name: 'Remove' })).toBeVisible()
  await expect(picture.locator('.media-source-note')).toBeHidden()
  expect(await takesDrag(picture)).toBe(true)

  const gallery = page.locator('[b-ref="slides"] .gallery-upload-wrapper')
  await expect(gallery.locator('.gallery-buttons')).toBeVisible()
  await expect(gallery.locator('.media-source-note')).toBeHidden()
  expect(await takesDrag(gallery)).toBe(true)

  await expect(page.locator('.block-vars .variable.image .media-action-menu')).toBeVisible()
})
