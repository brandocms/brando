import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The editor's init payload, as LiveView hands every pushed event to the window too.
async function recordEditorPayloads(page) {
  await page.evaluate(() => {
    window.__imageEditorPayloads = []
    window.addEventListener('phx:b:image_editor:init', e => window.__imageEditorPayloads.push(e.detail))
  })
}

const lastEditorPayload = page => page.evaluate(() => window.__imageEditorPayloads.at(-1))

// How far the 3:2 preview's band is from each candidate region of the source,
// as the mean difference per channel: 0 when the preview shows exactly it.
async function previewDistances(page, src, regions) {
  return page.evaluate(async ({ src, regions }) => {
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.src = src
    await img.decode()
    const preview = document.querySelector('#image-editor-previews canvas')
    const { width, height } = preview
    const shown = preview.getContext('2d').getImageData(0, 0, width, height).data

    return regions.map(r => {
      const canvas = document.createElement('canvas')
      canvas.width = width
      canvas.height = height
      const ctx = canvas.getContext('2d')
      ctx.drawImage(img, r.left, r.top, r.width, r.height, 0, 0, width, height)
      const expected = ctx.getImageData(0, 0, width, height).data
      let sum = 0
      for (let i = 0; i < expected.length; i++) sum += Math.abs(expected[i] - shown[i])
      return sum / expected.length
    })
  }, { src, regions })
}

async function openEditor(page) {
  const details = page.getByRole('dialog', { name: 'Image details', exact: true })
  await page.locator('#project_listing_image-media').getByRole('button', { name: 'Configure', exact: true }).click()
  await details.getByRole('button', { name: 'Edit/Crop', exact: true }).click()
  await expect(page.locator('#image-editor-drawer')).toBeVisible()
  // The hook clears aria-busy once the image is drawn on the canvas.
  await expect(page.locator('#image-editor-hook')).toHaveAttribute('aria-busy', 'false', { timeout: 15000 })
  await expect(page.locator('#image-editor-dimensions')).toHaveText(/^[1-9]\d* × [1-9]\d*$/)
  return details
}

test('an image placed in position mode keeps its mode and point when saved untouched', async ({ page }) => {
  test.setTimeout(120000)

  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'PosFocalClient', slug: 'posfocalclient', status: 'published', language: 'en',
  })
  const uploaded = await factory(page, 'E2eProject.Projects.Project', {
    title: 'PosFocalUpload', slug: 'posfocalupload', client_id: client.id,
    introduction: '<p>Intro</p>', status: 'published', language: 'en',
  })

  // A file on disk to process: upload one through the field, save it (an
  // upload left unsaved is discarded with its file), and read its original's
  // path from the editor.
  await page.goto(`/admin/projects/projects/update/${uploaded.id}`)
  await syncLV(page)
  const imageField = page.locator('#project_listing_image-media')
  await imageField.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
  await expect(imageField.locator('img')).toBeVisible({ timeout: 30000 })
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/, { timeout: 30000 })
  await page.goto(`/admin/projects/projects/update/${uploaded.id}`)
  await syncLV(page)
  await recordEditorPayloads(page)
  await openEditor(page)
  const source = await lastEditorPayload(page)
  expect(source.focal_mode).toBe('center')

  // The same file as an image whose focal point is in position mode, as the
  // Figma import sets it, with a coordinate at 0.
  expect([source.image_width, source.image_height]).toEqual([292, 173])
  const path = new URL(source.image_src, page.url()).pathname.replace(/^\/media\//, '')
  const image = await factory(page, 'Brando.Images.Image', {
    path,
    // Not the original: processing deletes the old sizes before it writes new ones
    sizes: { thumb: path.replace(/[^/]+$/, 'thumb/$&') },
    width: source.image_width,
    height: source.image_height,
    config_target: source.config_target,
    status: 'processed',
    focal: { x: 75, y: 0, mode: 'position' },
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'PosFocalTest', slug: 'posfocaltest', client_id: client.id, listing_image_id: image.id,
    introduction: '<p>Intro</p>', status: 'published', language: 'en',
  })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await recordEditorPayloads(page)
  await openEditor(page)
  expect(await lastEditorPayload(page)).toMatchObject({ image_id: image.id, focal_x: 75, focal_y: 0, focal_mode: 'position' })

  // The 3:2 frame is 260 × 173 of the 292 × 173 image. The server cuts it at
  // 0.75 × (292 − 260) = 24 from the left; centred on the point it would
  // start at 89, clamped to 32.
  const placed = { left: 24, top: 0, width: 260, height: 173 }
  const centred = { left: 32, top: 0, width: 260, height: 173 }
  const [onPlaced, onCentred] = await previewDistances(page, source.image_src, [placed, centred])
  expect(onPlaced).toBeLessThan(1)
  expect(onCentred).toBeGreaterThan(onPlaced + 1)

  const details = page.getByRole('dialog', { name: 'Image details', exact: true })
  await page.locator('#image-editor-save-replace').click()
  await expect(page.locator('#image-editor-drawer')).toBeHidden()
  await syncLV(page, 30000)
  await details.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(details).toBeHidden()

  // Read back from the database rather than from the open form.
  await page.reload()
  await syncLV(page)
  await recordEditorPayloads(page)
  await openEditor(page)
  expect(await lastEditorPayload(page)).toMatchObject({ image_id: image.id, focal_x: 75, focal_y: 0, focal_mode: 'position' })

  // Dragging the frame reads the point in centre mode from there on, from the
  // centre of the frame as it stood: a drag that comes back to where it
  // started leaves the frame where it was.
  const canvas = await page.locator('#image-editor-canvas').boundingBox()
  const grab = { x: canvas.x + canvas.width / 2, y: canvas.y + canvas.height / 2 }
  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  await page.mouse.move(grab.x - 20, grab.y, { steps: 4 })
  await page.mouse.move(grab.x, grab.y, { steps: 4 })
  await page.mouse.up()
  const [afterDrag] = await previewDistances(page, source.image_src, [placed])
  expect(afterDrag).toBeLessThan(1)
})
