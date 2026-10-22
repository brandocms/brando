import fs from 'node:fs'
import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Video fields configured for a provider upload to it, end to end, against
// the E2E app's fake Bunny (E2EFakeBunny): the browser sends the file over tus
// to `/e2e/bunny/tus`, which reports the encode finished through Brando's own
// webhook handling, so the video is ready when the field takes it. Its
// thumbnail is on the fake's CDN hostname, answered here.

const BUNNY_CDN = 'https://bunny-cdn.e2e.test/**'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function openProject(page, title) {
  await page.route(BUNNY_CDN, route => route.fulfill({ path: './fixtures/image.jpg', contentType: 'image/jpeg' }))
  await page.setViewportSize({ width: 1440, height: 1000 })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Bunny', slug: 'bunny', status: 'published', language: 'en' })
  const slug = title.toLowerCase().replaceAll(' ', '-')
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title, slug, client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  return project
}

async function drop(page, target, name, type) {
  const bytes = [...fs.readFileSync(`./fixtures/${name}`)]
  const transfer = await page.evaluateHandle(({ name, type, bytes }) => {
    const transfer = new DataTransfer()
    transfer.items.add(new File([new Uint8Array(bytes)], name, { type }))
    return transfer
  }, { name, type, bytes })
  await target.dispatchEvent('dragenter', { dataTransfer: transfer })
  await target.dispatchEvent('drop', { dataTransfer: transfer })
  await transfer.dispose()
}

// The field shows the uploaded video, with the dimensions Bunny reported once
// the encode finished.
async function expectBunnyVideo(field) {
  await expect(field).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
  await expect(field.locator('.media-field-name')).toHaveText('Video')
  await expect(field.locator('.media-field-meta')).toHaveText('Video · 16:9')
  return field.getAttribute('data-asset-id')
}

async function expectSaved(page, project, field, videoId) {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await expect(field).toHaveAttribute('data-asset-id', videoId)
}

const bunnyField = page => page.locator('#project_bunny_video-media')

test('a video uploaded on a Bunny field goes to Bunny and is kept on save', async ({ page }) => {
  const project = await openProject(page, 'Bunny upload')
  const field = bunnyField(page)
  await expect(field).toHaveAttribute('data-upload-enabled', 'true')
  await expect(page.locator('#project_bunny_video-video-uploader')).toHaveAttribute('phx-hook', 'Brando.BunnyUploader')

  const chooser = page.waitForEvent('filechooser')
  await field.getByRole('button', { name: 'Upload', exact: true }).click()
  await (await chooser).setFiles('./fixtures/video.mp4')

  const videoId = await expectBunnyVideo(field)
  await expectSaved(page, project, field, videoId)
})

test('a video dropped on a Bunny field goes to Bunny and is kept on save', async ({ page }) => {
  const project = await openProject(page, 'Bunny drop')
  const field = bunnyField(page)
  await expect(field).toHaveAttribute('data-upload-enabled', 'true')

  await drop(page, field, 'video.mp4', 'video/mp4')

  const videoId = await expectBunnyVideo(field)
  await expectSaved(page, project, field, videoId)
})

// #3259: the picker handed its upload to the field, whose update raised, and
// the form went down with the video unselected.
test("a video uploaded in the picker opened by a Bunny field is set on the field", async ({ page }) => {
  const project = await openProject(page, 'Bunny picker')
  const field = bunnyField(page)
  const picker = page.locator('#video-picker')

  await field.getByRole('button', { name: 'Select video', exact: true }).click()
  await expect(picker).toBeVisible()
  const uploader = picker.locator('[phx-hook="Brando.BunnyUploader"]')
  await expect(uploader.getByRole('button', { name: 'Upload file' })).toBeVisible()
  await uploader.locator('input[type="file"]').setInputFiles('./fixtures/video.mp4')

  const videoId = await expectBunnyVideo(field)
  // Ready, so the picker shows Bunny's thumbnail rather than a broken image.
  const thumbnail = picker.locator(`.video-preview[phx-value-video-id="${videoId}"] img`)
  await expect(thumbnail).toHaveAttribute('src', /^https:\/\/bunny-cdn\.e2e\.test\/[0-9a-f-]{36}\/thumbnail\.jpg$/)
  await expect.poll(() => thumbnail.evaluate(img => img.complete && img.naturalWidth)).toBeGreaterThan(0)
  await picker.locator('.drawer-close-button').first().click()
  await expect(picker).toBeHidden()
  await syncLV(page)
  await expect(page.locator('.phx-error')).toHaveCount(0)
  await expectSaved(page, project, field, videoId)
})

test('a field with uploads off refuses a dropped video', async ({ page }) => {
  await openProject(page, 'No upload drop')
  const field = page.locator('#project_no_upload_video-media')
  await expect(field).toHaveAttribute('data-upload-enabled', 'false')

  await drop(page, field, 'video.mp4', 'video/mp4')

  await expect(field.locator('.media-field-progress')).toHaveAttribute('data-state', 'error')
  await expect(field.locator('.media-field-progress')).toContainText("Video upload isn't set up.")
  await expect(field).not.toHaveAttribute('data-asset-id', /./)
})
