import { test, expect } from '../../test-support/setupAuth'
import { syncLV, toggleLivePreview, getPreviewFrame, waitForPreviewReady } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// A gallery video's playback settings are Default / On / Off, and the live
// preview plays it as they say (#4020). Its switches had no effect: the
// video played with its own settings whatever they showed.
test('a gallery video plays in the live preview as its playback settings say', async ({ page }) => {
  test.setTimeout(90000)

  const video = await factory(page, 'Brando.Videos.Video', {
    type: 'external_file',
    source_url: 'https://example.com/gallery-playback.mp4',
    title: 'Gallery playback',
    config_target: 'default',
    status: 'ready',
    autoplay: true,
  })

  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Gallery Playback Page')
  await page.getByLabel('URI').fill('gallery-playback')

  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
  await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
  await page.getByRole('button', { name: 'Gallery with Controls' }).click()
  await syncLV(page)

  await toggleLivePreview(page)
  await waitForPreviewReady(page)
  const frame = getPreviewFrame(page)

  const gallery = page.locator('.gallery-block')
  await gallery.getByRole('button', { name: 'Select videos', exact: true }).click()
  await syncLV(page)
  await page.locator(`#video-picker .video-picker__video[data-id="${video.id}"]`).click()
  await syncLV(page)
  await page.locator('#video-picker').getByRole('button', { name: 'Close', exact: true }).click()
  await expect(gallery.locator('.gallery-object')).toHaveCount(1)

  // Reopened, the preview renders the entry as the form holds it. An open
  // preview keeps a booted player as it is while its source is unchanged
  // (`block_patch.js`), so a playback change shows from the next render.
  const previewAutoplay = async () => {
    await toggleLivePreview(page)
    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    return frame.locator('[data-gallery] [data-smart-video]').first()
  }

  const dialog = page.getByRole('dialog').filter({ has: page.getByRole('group', { name: 'Autoplay' }) })
  const autoplay = dialog.getByRole('group', { name: 'Autoplay' })

  const choose = async choice => {
    await gallery.locator('.gallery-object').getByRole('button', { name: 'Configure' }).click()
    await autoplay.getByText(choice, { exact: true }).click()
    await syncLV(page)
    await expect(autoplay.getByRole('radio', { name: choice })).toBeChecked()
    await dialog.getByRole('button', { name: 'Close dialog' }).click()
  }

  await expect(await previewAutoplay()).toHaveAttribute('data-autoplay')

  await gallery.locator('.gallery-object').getByRole('button', { name: 'Configure' }).click()
  await expect(autoplay.getByRole('radio', { name: 'Default' })).toBeChecked()
  await dialog.getByRole('button', { name: 'Close dialog' }).click()

  await choose('Off')
  await expect(await previewAutoplay()).not.toHaveAttribute('data-autoplay')

  await choose('On')
  await expect(await previewAutoplay()).toHaveAttribute('data-autoplay')

  await choose('Off')
  await expect(await previewAutoplay()).not.toHaveAttribute('data-autoplay')

  // Default follows the video, which autoplays
  await choose('Default')
  await expect(await previewAutoplay()).toHaveAttribute('data-autoplay')
})
