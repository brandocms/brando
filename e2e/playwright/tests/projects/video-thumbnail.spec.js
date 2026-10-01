import { test, expect } from '../../test-support/setupAuth'
import { keepDuplicateUploads, syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The video drawer's "Select from library" sets the image picker up for the
// video's thumbnail. It used to open the picker as the last field had left it,
// so a pick replaced that field's image instead.
test("a video's thumbnail is picked from the library without touching other fields", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const listing = await factory(page, 'Brando.Images.Image', {
    path: 'images/listing-cover.jpg', sizes: { thumb: 'images/listing-cover.jpg' }, width: 292, height: 173,
    status: 'processed', focal: { x: 50, y: 50 },
  })
  const video = await factory(page, 'Brando.Videos.Video', {
    type: 'external_file', source_url: 'https://example.com/thumbnail-clip.mp4', title: 'Thumbnail clip', status: 'ready',
  })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Thumbs', slug: 'thumbs', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Video thumbnail', slug: 'video-thumbnail', client_id: client.id, status: 'published', language: 'en',
    introduction: '<p>Intro</p>', listing_image_id: listing.id, cover_video_id: video.id,
  })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  const listingField = page.locator('#project_listing_image-media')
  const picker = page.locator('#image-picker')
  const drawer = page.locator('#video-drawer')

  // Leave the picker set up for the listing image, as an editor would.
  await listingField.getByRole('button', { name: 'Select image', exact: true }).first().click()
  await expect(picker).toBeVisible()
  await picker.locator('.drawer-close-button').first().click()
  await expect(picker).toBeHidden()

  await page.locator('#project_cover_video-media').getByRole('button', { name: 'Configure', exact: true }).click()
  await expect(drawer).toBeVisible()
  await drawer.getByRole('button', { name: 'Select from library', exact: true }).click()
  await expect(picker.locator('.image-picker-main-header h3')).toHaveText('images/videos/thumbnails')

  await picker.locator('input[type="file"]').first().setInputFiles('./fixtures/image.jpg')
  await keepDuplicateUploads(page)
  const row = picker.locator('.image-picker__image').first()
  await expect(row).toBeVisible({ timeout: 30000 })
  const thumbnailId = await row.getAttribute('data-id')
  await row.click()
  await expect(picker).toBeHidden()
  await syncLV(page)

  await expect(drawer.locator('.video-detail-thumbnail img')).toBeVisible()
  await expect(listingField).toHaveAttribute('data-asset-id', String(listing.id))

  // Opened again, the picker marks the current thumbnail.
  await drawer.getByRole('button', { name: 'Select from library', exact: true }).click()
  await expect(picker.locator(`.image-picker__image[data-id="${thumbnailId}"]`)).toHaveClass(/selected/)
  await picker.locator('.drawer-close-button').first().click()

  // Saved straight away, like "Remove": still there after a reload.
  await page.reload()
  await syncLV(page)
  await page.locator('#project_cover_video-media').getByRole('button', { name: 'Configure', exact: true }).click()
  await expect(drawer.locator('.video-detail-thumbnail img')).toBeVisible()
})
