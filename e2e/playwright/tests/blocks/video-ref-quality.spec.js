import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A video ref's Quality (#3284): the Playback section of its settings offers
// the qualities its Bunny video has, and the one picked is saved with the
// entry. The fixture's page holds a Video Player block whose ref shows a
// ready Bunny video with MP4s at 360p and 720p.
test('a video ref keeps the quality picked in its settings', async ({ page }) => {
  const response = await page.request.post('/e2e/video-quality-fixtures')
  expect(response.ok(), await response.text()).toBeTruthy()
  const { page_id: pageId } = await response.json()
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  const openPlayback = async () => {
    await page.goto(`/admin/pages/update/${pageId}`)
    await syncLV(page)
    await page.locator('.video-block').getByRole('button', { name: 'Konfigurer blokk' }).click()
    const modal = page.locator('.modal:visible').filter({ has: page.getByRole('tab', { name: 'Avspilling' }) })
    await modal.getByRole('tab', { name: 'Avspilling' }).click()
    return modal
  }

  let modal = await openPlayback()
  const quality = modal.getByLabel('Kvalitet')
  const values = await quality.locator('option').evaluateAll(options => options.map(option => option.value))
  expect(values).toEqual(['', 'auto', 'hls', 'mp4_360', 'mp4_720'])
  await expect(quality).toHaveValue('')

  await quality.selectOption('mp4_720')
  await syncLV(page)
  await modal.getByRole('button', { name: 'Ferdig' }).click()
  await syncLV(page)
  // Saving closes the entry
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })

  modal = await openPlayback()
  await expect(modal.getByLabel('Kvalitet')).toHaveValue('mp4_720')
})
