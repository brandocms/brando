import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// "Add from Bunny Stream" browses the account's library by collection, in the
// Videos library and in the video picker, which share the panel. The E2E
// server answers Bunny itself (E2EFakeBunny): three videos, two in
// "Coastline" and one in "Interviews".

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

function row(panel, title) {
  return panel.locator('.video-picker-library-item').filter({ hasText: title })
}

test('the Videos library lists a collection at a time, and searches within it', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.route('https://bunny-cdn.e2e.test/**', route => route.fulfill({ status: 404 }))
  await page.goto('/admin/assets/videos')
  await syncLV(page)

  await page.getByRole('button', { name: 'Add from Bunny Stream', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Add from Bunny Stream' })
  const titles = dialog.locator('.video-picker-library-title')
  const collection = dialog.getByRole('combobox', { name: 'Collection' })

  // All videos to start with, each naming its collection
  await expect(titles).toHaveText(['Harbour at dawn', 'Studio interview', 'Night ferry'])
  await expect(collection).toHaveValue('')
  await expect(collection.locator('option')).toHaveText(['All videos', 'Coastline · 2', 'Interviews · 1'])
  await expect(row(dialog, 'Harbour at dawn').locator('.video-picker-library-meta')).toContainText('Coastline · ')
  await expect(row(dialog, 'Studio interview').locator('.video-picker-library-meta')).toContainText('Interviews · ')

  // One collection: its videos, which need not name it
  await collection.selectOption({ label: 'Coastline · 2' })
  await expect(titles).toHaveText(['Harbour at dawn', 'Night ferry'])
  await expect(row(dialog, 'Night ferry').locator('.video-picker-library-meta')).not.toContainText('Coastline')

  // A search runs within it, and the collection stays chosen
  await dialog.getByRole('searchbox', { name: 'Search Bunny Stream' }).fill('ferry')
  await dialog.getByRole('button', { name: 'Search', exact: true }).click()
  await expect(titles).toHaveText(['Night ferry'])
  await expect(collection).toHaveValue(/c011ec71/)

  // Another collection keeps the search: nothing there matches it
  await collection.selectOption({ label: 'Interviews · 1' })
  await expect(dialog.locator('.video-picker-library-item')).toHaveCount(0)
  await expect(dialog.locator('.video-picker-library-note')).toBeVisible()

  await dialog.getByRole('searchbox', { name: 'Search Bunny Stream' }).fill('')
  await dialog.getByRole('button', { name: 'Search', exact: true }).click()
  await expect(titles).toHaveText(['Studio interview'])

  // Added from the collection like any other
  await row(dialog, 'Studio interview').getByRole('button', { name: 'Add', exact: true }).click()
  await expect(row(dialog, 'Studio interview').locator('.video-picker-library-status')).toBeVisible()
  await expect(page.locator('.phx-error')).toHaveCount(0)
})

test('the video picker offers the same collections', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.route('https://bunny-cdn.e2e.test/**', route => route.fulfill({ status: 404 }))

  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Collections', slug: 'collections', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Picker collections', slug: 'picker-collections', client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const picker = page.locator('#video-picker')
  await page.locator('#project_cover_video-media').getByRole('button', { name: 'Select video', exact: true }).click()
  await expect(picker).toBeVisible()

  await picker.getByRole('button', { name: 'Add from Bunny Stream', exact: true }).click()
  const panel = picker.getByRole('region', { name: 'Bunny Stream library' })
  const titles = panel.locator('.video-picker-library-title')

  await expect(titles).toHaveText(['Harbour at dawn', 'Studio interview', 'Night ferry'])
  await panel.getByRole('combobox', { name: 'Collection' }).selectOption({ label: 'Interviews · 1' })
  await expect(titles).toHaveText(['Studio interview'])
  await expect(page.locator('.phx-error')).toHaveCount(0)
})
