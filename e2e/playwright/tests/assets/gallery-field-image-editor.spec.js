import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const mediaState = async (page, id) => {
  const response = await page.request.post('/e2e/drafts/media-state', { data: { schema: 'project', entry_id: String(id) } })
  expect(response.ok()).toBeTruthy()
  return response.json()
}

// The gallery field's editor is opened from the field, not from the image
// drawer, so its copy cannot go through the drawer's file input: the field
// takes it in the edited object's place.
test('save as new copy in a gallery field replaces the edited image', async ({ page }) => {
  test.setTimeout(120000)

  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'GalleryCopyClient',
    slug: 'gallerycopyclient',
    status: 'published',
    language: 'en',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'GalleryCopyTest',
    slug: 'gallerycopytest',
    client_id: client.id,
    introduction: '<p>Test introduction</p>',
    status: 'published',
    language: 'en',
  })
  const path = `/admin/projects/projects/update/${project.id}`
  await page.goto(path)
  await syncLV(page)

  const gallery = page.locator('.gallery-input')
  const objects = gallery.locator('.gallery-object')
  const chooser = page.waitForEvent('filechooser')
  await gallery.getByRole('button', { name: 'Upload', exact: true }).click()
  await (await chooser).setFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
  await expect(objects).toHaveCount(2, { timeout: 30000 })
  await expect(objects.locator('img')).toHaveCount(2, { timeout: 30000 })
  await syncLV(page)

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/projects\/projects$/, { timeout: 30000 })
  await page.goto(path)
  await syncLV(page)

  const saved = (await mediaState(page, project.id)).entry.project_gallery.gallery_objects
  expect(saved).toHaveLength(2)
  const [first, second] = saved.map(row => row.image_id)

  await objects.first().locator('.edit-image-btn').click()
  const editor = page.locator('#image-editor-drawer')
  await expect(editor).toBeVisible()
  await expect(page.locator('#image-editor-hook')).toHaveAttribute('aria-busy', 'false', { timeout: 15000 })
  await expect(page.locator('#image-editor-dimensions')).toHaveText(/^[1-9]\d* × [1-9]\d*$/)

  await page.locator('#image-editor-save-new').click()
  await expect(editor).toBeHidden({ timeout: 10000 })

  // The copy takes the first object's place; the second stays where it was.
  await expect.poll(() => objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))).not.toEqual([first, second])
  const ids = await objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))
  expect(ids).toHaveLength(2)
  expect(ids[0]).not.toBe(first)
  expect(ids[1]).toBe(second)
  await expect(objects.locator('img')).toHaveCount(2, { timeout: 30000 })
  await syncLV(page)

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/projects\/projects$/, { timeout: 30000 })

  const state = await mediaState(page, project.id)
  expect(state.entry.project_gallery.gallery_objects.map(row => row.image_id)).toEqual(ids)
})
