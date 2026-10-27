import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The video picker's own search narrows the videos listed for the field, as
// the image picker's does; a provider's library keeps its search in its panel.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('the video picker lists only the videos matching its search', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const configTarget = 'video:E2eProject.Projects.Project:cover_video'

  for (const [title, slug] of [['Harbour at dawn', 'harbour'], ['Studio interview', 'studio']]) {
    await factory(page, 'Brando.Videos.Video', {
      type: 'external_file', source_url: `https://example.com/${slug}.mp4`, title, status: 'ready', config_target: configTarget,
    })
  }

  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Search', slug: 'search', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Picker search', slug: 'picker-search', client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const picker = page.locator('#video-picker')
  const titles = picker.locator('.video-picker__video .video-picker__title')

  await page.locator('#project_cover_video-media').getByRole('button', { name: 'Select video', exact: true }).click()
  await expect(picker).toBeVisible()
  await expect(titles).toHaveText(['Studio interview', 'Harbour at dawn'])

  const search = picker.getByRole('searchbox', { name: 'Search videos in this folder' })
  await search.fill('harbour')
  await expect(titles).toHaveText(['Harbour at dawn'])

  await search.fill('nothing like it')
  await expect(titles).toHaveCount(0)
  await expect(picker.getByRole('heading', { name: 'No videos match “nothing like it”.' })).toBeVisible()

  await picker.getByRole('button', { name: 'Clear search' }).click()
  await expect(titles).toHaveText(['Studio interview', 'Harbour at dawn'])
  await expect(search).toHaveValue('')
})
