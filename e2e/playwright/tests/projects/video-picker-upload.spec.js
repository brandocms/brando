import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A video uploaded to the server in the picker carries the picker's opening
// through the upload manager (`data-ref` on its trigger), and the picker hands
// it to the field of that opening (#3276). The race itself, another field
// opening the picker during the transfer, is covered by
// test/brando_admin/live/video_picker_upload_test.exs; a local upload of the
// fixture is over before a browser could reopen the picker.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('a video uploaded to the server in the picker is set on the field that opened it', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Picker', slug: 'picker', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Picker upload', slug: 'picker-upload', client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const field = page.locator('#project_cover_video-media')
  const other = page.locator('#project_no_upload_video-media')
  const picker = page.locator('#video-picker')

  await field.getByRole('button', { name: 'Select video', exact: true }).click()
  await expect(picker).toBeVisible()
  const trigger = picker.locator('#video-uploader-video-picker')
  await expect(trigger).toHaveAttribute('data-ref', /^vp-\d+$/)
  await expect(trigger).toHaveAttribute('data-expected-asset-id', 'none')
  await trigger.locator('input[type="file"]').setInputFiles('./fixtures/video.mp4')

  await expect(field).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
  const videoId = await field.getAttribute('data-asset-id')
  await expect(other).not.toHaveAttribute('data-asset-id', /^\d+$/)

  await picker.locator('.drawer-close-button').first().click()
  await expect(picker).toBeHidden()
  await syncLV(page)
  await expect(page.locator('.phx-error')).toHaveCount(0)

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await expect(field).toHaveAttribute('data-asset-id', videoId)
})
