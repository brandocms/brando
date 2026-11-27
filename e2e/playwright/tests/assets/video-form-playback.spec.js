import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The Edit video form shows each playback setting as Default / On / Off, as
// the video drawer does (#4004). Its switches stored Off for every setting
// left alone, so a save made a lazy video eager.
test('saving a video keeps the playback settings it was given', async ({ page }) => {
  const video = await factory(page, 'Brando.Videos.Video', {
    type: 'external_file', source_url: 'https://example.com/harbour.mp4', title: 'Harbour loop', status: 'ready', loop: true,
  })

  const setting = name =>
    page.locator('[data-component="radios"]').filter({ has: page.getByText(name, { exact: true }) })

  const open = async () => {
    await page.goto(`/admin/assets/videos/update/${video.id}`)
    await syncLV(page)
  }

  const saveAndClose = async () => {
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/assets\/videos$/, { timeout: 30000 })
  }

  await open()
  await expect(setting('Lazy load').getByRole('radio', { name: 'Default' })).toBeChecked()
  await expect(setting('Loop').getByRole('radio', { name: 'On' })).toBeChecked()
  await saveAndClose()

  await open()
  await expect(setting('Lazy load').getByRole('radio', { name: 'Default' })).toBeChecked()
  await expect(setting('Autoplay').getByRole('radio', { name: 'Default' })).toBeChecked()
  await expect(setting('Loop').getByRole('radio', { name: 'On' })).toBeChecked()

  await setting('Lazy load').getByRole('radio', { name: 'Off' }).check()
  await syncLV(page)
  await saveAndClose()

  await open()
  await expect(setting('Lazy load').getByRole('radio', { name: 'Off' })).toBeChecked()
})
