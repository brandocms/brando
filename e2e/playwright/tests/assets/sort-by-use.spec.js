import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// "Sort by use" and "Delete unused" in the video and file libraries (#3098).
// Driven in Norwegian, so the locators name the translated labels. The
// fixture puts four videos and four files in a "Sweep" folder of each
// library: pages use three of each, one of each is used nowhere.

test.use({ viewport: { width: 1440, height: 1000 } })

async function fixtures(page) {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  const response = await page.request.post('/e2e/media-sweep-fixtures')
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('videos are sorted into a folder per entry, and the sort is undone', async ({ page }) => {
  const { video_folder_id } = await fixtures(page)
  await page.goto(`/admin/assets/videos?filter:folder_id=${video_folder_id}`)
  await syncLV(page)
  await expect(page.locator('.list-row')).toHaveCount(4)

  await page.getByRole('button', { name: 'Sorter etter bruk' }).click()
  const dialog = page.locator('#video-sweep')
  await expect(dialog.locator('.media-sweep-group')).toHaveCount(2)
  // The translation shares its entry's folder: the campaign has both its videos.
  const campaign = dialog.locator('.media-sweep-group').filter({ hasText: 'Spring campaign' })
  await expect(campaign.locator('.media-sweep-thumbs img')).toHaveCount(2)

  // Rename one folder and leave the other entry's videos where they are.
  await dialog.getByRole('textbox', { name: 'Mappe for Spring campaign' }).fill('kampanjer/var')
  await dialog
    .locator('.media-sweep-group')
    .filter({ hasText: 'Studio visits' })
    .getByRole('checkbox', { name: 'Flytt disse' })
    .uncheck()
  await page.getByRole('button', { name: 'Flytt videoene' }).click()

  await expect(page.getByTestId('sweep-result')).toBeVisible()
  await expect(dialog).toHaveCount(0)
  await expect(page.locator('.list-row')).toHaveCount(2)
  await expect(page.getByRole('button', { name: 'kampanjer', exact: true })).toBeVisible()

  await page.getByTestId('sweep-result').getByRole('button', { name: 'Angre' }).click()
  await expect(page.getByTestId('sweep-result')).toHaveCount(0)
  await expect(page.locator('.list-row')).toHaveCount(4)
  await expect(page.getByRole('button', { name: 'kampanjer', exact: true })).toHaveCount(0)
})

test('unused videos and files are deleted after a confirmation', async ({ page }) => {
  const { video_folder_id, file_folder_id } = await fixtures(page)

  for (const [library, folder] of [['videos', video_folder_id], ['files', file_folder_id]]) {
    await page.goto(`/admin/assets/${library}?filter:folder_id=${folder}&filter:unused=true`)
    await syncLV(page)
    await expect(page.locator('.list-row')).toHaveCount(1)
    await expect(page.getByRole('button', { name: 'Sorter etter bruk' })).toHaveCount(0)

    // Cancelling keeps it.
    await page.getByRole('button', { name: 'Slett 1 ubrukt' }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Avbryt' }).click()
    await expect(page.locator('.list-row')).toHaveCount(1)

    await page.getByRole('button', { name: 'Slett 1 ubrukt' }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Slett' }).click()
    await expect(page.locator('.list-row')).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Slett 1 ubrukt' })).toHaveCount(0)
  }
})

test('the file preview shows each file by its type', async ({ page }) => {
  const { file_folder_id } = await fixtures(page)
  await page.goto(`/admin/assets/files?filter:folder_id=${file_folder_id}`)
  await syncLV(page)

  await page.getByRole('button', { name: 'Sorter etter bruk' }).click()
  const campaign = page.locator('#file-sweep .media-sweep-group').filter({ hasText: 'Spring campaign' })
  await expect(campaign.locator('.media-sweep-tile .lucide-file-spreadsheet')).toHaveCount(1)
  await expect(campaign.locator('.media-sweep-tile .lucide-file-text')).toHaveCount(1)

  await page.getByRole('button', { name: 'Flytt filene' }).click()
  await expect(page.getByTestId('sweep-result')).toBeVisible()
  await expect(page.locator('.list-row')).toHaveCount(1)
})
