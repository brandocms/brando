import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The Videos library's "Add from URL": the address is read in the browser,
// its title looked up at the provider, and the video goes into the folder in
// view. The E2E server answers YouTube's oEmbed itself (`E2EFakeOEmbed`).
test('adds a video from its URL into the folder in view', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/assets/videos')
  await syncLV(page)

  const rows = page.locator('.content-list .list-row')
  const rootCount = await rows.count()

  await page.getByRole('button', { name: 'New folder', exact: true }).click()
  await page.getByPlaceholder('Folder name', { exact: true }).fill('url-adds')
  await page.getByRole('button', { name: 'Create folder', exact: true }).click()
  const path = page.getByRole('navigation', { name: 'Folder path' })
  await expect(path).toContainText('url-adds')
  await expect(page.getByRole('heading', { name: 'No videos in this view' })).toBeVisible()
  await syncLV(page)

  await page.getByRole('button', { name: 'Add from URL', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Add from URL' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByLabel('Video URL')).toBeFocused()

  await dialog.getByLabel('Video URL').fill('https://www.youtube.com/watch?v=dQw4w9WgXcQ')
  await dialog.getByRole('button', { name: 'Create video' }).click()

  await expect(dialog).toBeHidden({ timeout: 15000 })
  await expect(rows).toHaveCount(1)
  await expect(rows.first().locator('input[name="title"]')).toHaveValue('Fake oEmbed title')
  await expect(page.locator('.image-picker-main-actions > span').first()).toHaveText('1 video')
  const addedId = await rows.first().getAttribute('id')

  // Not at the root: it went into the folder
  await page.getByRole('button', { name: 'Root', exact: true }).click()
  await expect(path).not.toContainText('url-adds')
  await expect(rows).toHaveCount(rootCount)
  await expect(page.locator(`#${addedId}`)).toHaveCount(0)
  await expect(page.locator('.phx-error')).toHaveCount(0)
})

test('closing the dialog leaves the library as it was', async ({ page }) => {
  await page.goto('/admin/assets/videos')
  await syncLV(page)

  await page.getByRole('button', { name: 'Add from URL', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Add from URL' })
  await expect(dialog).toBeVisible()

  await page.keyboard.press('Escape')
  await expect(dialog).toBeHidden()
  await expect(page.getByRole('button', { name: 'Add from URL', exact: true })).toBeVisible()
})
