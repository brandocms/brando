import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The Videos library's Upload button sends the file through the upload
// manager (the E2E server uploads videos to itself, `:local`) into the
// folder in view, and at the root into the root, the default video folder.
test('uploads a video into the folder in view, and at the root into the root', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/assets/videos')
  await syncLV(page)

  const rows = page.locator('.content-list .list-row')
  const count = page.locator('.image-picker-main-actions > span').first()
  const rootCount = await rows.count()

  await page.getByRole('button', { name: 'New folder', exact: true }).click()
  await page.getByPlaceholder('Folder name', { exact: true }).fill('launch-reels')
  await page.getByRole('button', { name: 'Create folder', exact: true }).click()
  const path = page.getByRole('navigation', { name: 'Folder path' })
  await expect(path).toContainText('launch-reels')
  await expect(page.getByRole('heading', { name: 'No videos in this view' })).toBeVisible()
  await syncLV(page)

  await page.getByLabel('Upload videos', { exact: true }).setInputFiles('./fixtures/video.mp4')
  await expect(rows).toHaveCount(1, { timeout: 20000 })
  await expect(rows.first().locator('input[name="title"]')).toHaveValue('video.mp4')
  await expect(rows.first()).toContainText('Uploaded file')
  await expect(count).toHaveText('1 video')
  const uploadedId = await rows.first().getAttribute('id')

  // Not at the root: it went into the folder
  await page.getByRole('button', { name: 'Root', exact: true }).click()
  await expect(path).not.toContainText('launch-reels')
  await expect(rows).toHaveCount(rootCount)
  await expect(page.locator(`#${uploadedId}`)).toHaveCount(0)
  await syncLV(page)

  await page.getByLabel('Upload videos', { exact: true }).setInputFiles('./fixtures/video.mp4')
  await expect(rows).toHaveCount(rootCount + 1, { timeout: 20000 })
  await expect(count).toHaveText(`${rootCount + 1} video${rootCount + 1 === 1 ? '' : 's'}`)
  await expect(page.locator('.phx-error')).toHaveCount(0)
})
