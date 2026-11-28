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

  // The open preview follows each change: a booted player is kept only while
  // its source and playback settings are unchanged (`block_patch.js`).
  const player = frame.locator('[data-gallery] [data-smart-video]').first()
  const playerVideo = player.locator('video[data-video]')

  const dialog = page.getByRole('dialog').filter({ has: page.getByRole('group', { name: 'Autoplay' }) })

  const choose = async (setting, choice) => {
    const group = dialog.getByRole('group', { name: setting })
    await gallery.locator('.gallery-object').getByRole('button', { name: 'Configure' }).click()
    await group.getByText(choice, { exact: true }).click()
    await syncLV(page)
    await expect(group.getByRole('radio', { name: choice })).toBeChecked()
    await dialog.getByRole('button', { name: 'Close dialog' }).click()
  }

  await expect(player).toHaveAttribute('data-autoplay')
  await expect(player).toHaveAttribute('data-booted')

  await gallery.locator('.gallery-object').getByRole('button', { name: 'Configure' }).click()
  await expect(dialog.getByRole('group', { name: 'Autoplay' }).getByRole('radio', { name: 'Default' })).toBeChecked()
  await dialog.getByRole('button', { name: 'Close dialog' }).click()

  await choose('Autoplay', 'Off')
  await expect(player).not.toHaveAttribute('data-autoplay')

  await choose('Autoplay', 'On')
  await expect(player).toHaveAttribute('data-autoplay')

  await choose('Autoplay', 'Off')
  await expect(player).not.toHaveAttribute('data-autoplay')

  // Default follows the video, which autoplays
  await choose('Autoplay', 'Default')
  await expect(player).toHaveAttribute('data-autoplay')

  // Settings the renderer puts on the `<video>` only
  await choose('Controls', 'On')
  await expect(playerVideo).toHaveAttribute('controls')
  await choose('Controls', 'Off')
  await expect(playerVideo).not.toHaveAttribute('controls')

  await expect(playerVideo).toHaveAttribute('loop')
  await choose('Loop', 'Off')
  await expect(playerVideo).not.toHaveAttribute('loop')
})
