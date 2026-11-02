import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The video picker's preview plays what the server builds from the stored row.
// A stored address is never an iframe's src. The changeset refuses a script-scheme
// address, so a row stored before that is covered in video_picker_preview_test.exs.

const YOUTUBE_EMBED = 'https://www.youtube.com/embed/dQw4w9WgXcQ?autoplay=1'
const CONFIG_TARGET = 'video:E2eProject.Projects.Project:cover_video'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function openPreview(page, slug, video) {
  // No request leaves the test; the iframe's src is what counts
  await page.route(/youtube\.com|vimeo\.com|example\.com/, (route) => route.abort())

  await factory(page, 'Brando.Videos.Video', { status: 'ready', config_target: CONFIG_TARGET, title: slug, ...video })
  const client = await factory(page, 'E2eProject.Projects.Client', { name: slug, slug, status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: slug, slug, client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const picker = page.locator('#video-picker')
  await page.locator('#project_cover_video-media').getByRole('button', { name: 'Select video', exact: true }).click()
  await expect(picker).toBeVisible()
  await picker.locator('.video-picker__video').filter({ hasText: slug }).locator('.video-preview').click()

  const modal = page.locator('#video-player-modal')
  await expect(modal.locator('.video-not-loaded')).toHaveCount(0)
  return modal
}

const embeds = [
  ['youtube-id', { type: 'youtube', source_url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', remote_id: 'dQw4w9WgXcQ' }, YOUTUBE_EMBED],
  ['youtube-address-only', { type: 'youtube', source_url: 'https://youtu.be/dQw4w9WgXcQ' }, YOUTUBE_EMBED],
  ['vimeo-address-only', { type: 'vimeo', source_url: 'https://vimeo.com/76979871/abcdef1234' }, 'https://player.vimeo.com/video/76979871?h=abcdef1234&autoplay=1'],
]

for (const [slug, video, src] of embeds) {
  test(`previews ${slug} in the provider's player`, async ({ page }) => {
    const modal = await openPreview(page, `preview-${slug}`, video)
    await expect(modal.locator('iframe')).toHaveAttribute('src', src)
  })
}

test('previews a linked file in a video element', async ({ page }) => {
  const modal = await openPreview(page, 'preview-file', { type: 'external_file', source_url: 'https://example.com/clip.mp4' })
  await expect(modal.locator('video source')).toHaveAttribute('src', 'https://example.com/clip.mp4')
  await expect(modal.locator('iframe')).toHaveCount(0)
})

test("an address that is not the provider's plays nothing", async ({ page }) => {
  const modal = await openPreview(page, 'preview-elsewhere', { type: 'youtube', source_url: 'https://example.com/elsewhere' })
  await expect(modal.locator('.video-not-supported')).toBeVisible()
  await expect(modal.locator('iframe')).toHaveCount(0)
})
