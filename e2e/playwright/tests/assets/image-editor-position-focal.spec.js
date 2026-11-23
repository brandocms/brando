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

// A file on disk to process: upload one through a field, save it (an upload
// left unsaved is discarded with its file), and read the editor's payload for
// it, which carries the original's path.
async function uploadSource(page, name) {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: `${name}Client`, slug: `${name.toLowerCase()}client`, status: 'published', language: 'en',
  })
  const uploaded = await factory(page, 'E2eProject.Projects.Project', {
    title: `${name}Upload`, slug: `${name.toLowerCase()}upload`, client_id: client.id,
    introduction: '<p>Intro</p>', status: 'published', language: 'en',
  })

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
  expect([source.image_width, source.image_height]).toEqual([292, 173])
  return { client, source }
}

// The same file as an image whose focal point is in position mode, as the
// Figma import sets it, on a project whose form is then open.
async function openOnPositionImage(page, { client, source }, focal, slug) {
  const path = new URL(source.image_src, page.url()).pathname.replace(/^\/media\//, '')
  const image = await factory(page, 'Brando.Images.Image', {
    path,
    // Not the original: processing deletes the old sizes before it writes new ones
    sizes: { thumb: path.replace(/[^/]+$/, 'thumb/$&') },
    width: source.image_width,
    height: source.image_height,
    config_target: source.config_target,
    status: 'processed',
    focal: { x: focal.x, y: focal.y, mode: 'position' },
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: slug, slug, client_id: client.id, listing_image_id: image.id,
    introduction: '<p>Intro</p>', status: 'published', language: 'en',
  })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await recordEditorPayloads(page)
  await openEditor(page)
  expect(await lastEditorPayload(page)).toMatchObject({ image_id: image.id, focal_x: focal.x, focal_y: focal.y, focal_mode: 'position' })
  return image
}

// Save over the image, then read it back from the database rather than from
// the open form.
async function saveAndReopen(page) {
  await page.locator('#image-editor-save-replace').click()
  return reopenAfterSave(page)
}

async function reopenAfterSave(page) {
  const details = page.getByRole('dialog', { name: 'Image details', exact: true })
  await expect(page.locator('#image-editor-drawer')).toBeHidden()
  await syncLV(page, 30000)
  await details.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(details).toBeHidden()

  await page.reload()
  await syncLV(page)
  await recordEditorPayloads(page)
  await openEditor(page)
  return lastEditorPayload(page)
}

// The 3:2 frame is 260 × 173 of the 292 × 173 image: 32 columns to move in.
const band = left => ({ left, top: 0, width: 260, height: 173 })

test('an image placed in position mode keeps its mode and point when saved untouched', async ({ page }) => {
  test.setTimeout(120000)

  const uploaded = await uploadSource(page, 'PosFocal')
  const { source } = uploaded
  // A coordinate at 0.
  const image = await openOnPositionImage(page, uploaded, { x: 75, y: 0 }, 'posfocaltest')

  // The server cuts the frame at 0.75 × (292 − 260) = 24 from the left;
  // centred on the point it would start at 89, clamped to 32.
  const placed = band(24)
  const [onPlaced, onCentred] = await previewDistances(page, source.image_src, [placed, band(32)])
  expect(onPlaced).toBeLessThan(1)
  expect(onCentred).toBeGreaterThan(onPlaced + 1)

  // A click on the frame that jitters by a pixel is not a drag: it leaves the
  // frame and the mode alone.
  const canvas = await page.locator('#image-editor-canvas').boundingBox()
  const grab = { x: canvas.x + canvas.width / 2, y: canvas.y + canvas.height / 2 }
  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  await page.mouse.move(grab.x + 1, grab.y)
  await page.mouse.up()

  expect(await saveAndReopen(page)).toMatchObject({ image_id: image.id, focal_x: 75, focal_y: 0, focal_mode: 'position' })

  // Dragging the frame reads the point in centre mode from there on, from the
  // centre of the frame as it stood: the frame follows the pointer to the
  // edge, and back to where it started.
  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  await page.mouse.move(grab.x - 200, grab.y, { steps: 4 })
  const [atEdge, stillPlaced] = await previewDistances(page, source.image_src, [band(0), placed])
  expect(atEdge).toBeLessThan(1)
  expect(stillPlaced).toBeGreaterThan(atEdge + 1)
  await page.mouse.move(grab.x, grab.y, { steps: 4 })
  await page.mouse.up()
  const [afterDrag] = await previewDistances(page, source.image_src, [placed])
  expect(afterDrag).toBeLessThan(1)
})

test('a position-mode image is saved in the mode the editor shows', async ({ page }) => {
  test.setTimeout(180000)

  const uploaded = await uploadSource(page, 'PosFocalSave')
  const { source } = uploaded

  // Dragged and saved: the point the drag ends on reads back as the one before
  // it, (45, 50), but in centre mode, and the frame stays where it was dragged.
  // Placed at 0.45 × 32 = 14; dragged against the left edge, its centre is
  // column 130, saved as 45 %; centred there it starts at column 1.
  await openOnPositionImage(page, uploaded, { x: 45, y: 50 }, 'posfocaldrag')
  const canvas = await page.locator('#image-editor-canvas').boundingBox()
  const grab = { x: canvas.x + canvas.width / 2, y: canvas.y + canvas.height / 2 }
  await page.mouse.move(grab.x, grab.y)
  await page.mouse.down()
  await page.mouse.move(grab.x - 200, grab.y, { steps: 4 })
  await page.mouse.up()
  const [dragged, placed] = await previewDistances(page, source.image_src, [band(0), band(14)])
  expect(dragged).toBeLessThan(1)
  expect(placed).toBeGreaterThan(dragged + 1)

  expect(await saveAndReopen(page)).toMatchObject({ focal_x: 45, focal_y: 50, focal_mode: 'center' })
  const [reopened, reopenedPlaced] = await previewDistances(page, source.image_src, [band(1), band(14)])
  expect(reopened).toBeLessThan(1)
  expect(reopenedPlaced).toBeGreaterThan(reopened + 1)

  // A corner resize scales the frame around its centre, column 154 and row
  // 86.5, rather than towards the position-mode anchor.
  await openOnPositionImage(page, uploaded, { x: 75, y: 0 }, 'posfocalresize')
  const box = await page.locator('#image-editor-canvas').boundingBox()
  const scale = box.width / source.image_width
  const corner = { x: box.x + 284 * scale - 3, y: box.y + 173 * scale - 3 }
  await page.mouse.move(corner.x, corner.y)
  await page.mouse.down()
  await page.mouse.move(corner.x - 65 * scale, corner.y - 43 * scale, { steps: 4 })
  await page.mouse.up()
  const zoom = parseFloat(await page.locator('#image-editor-zoom-value').textContent())
  expect(zoom).toBeGreaterThan(1.5)
  const width = Math.round(260 / zoom)
  const height = Math.round(173 / zoom)
  const clamp = (v, max) => Math.min(Math.max(0, v), max)
  const aroundCentre = {
    left: clamp(Math.round(154 - width / 2), 292 - width), top: clamp(Math.round(86.5 - height / 2), 173 - height), width, height,
  }
  const towardsAnchor = { left: Math.round(0.75 * (292 - width)), top: 0, width, height }
  const [onCentre, onAnchor] = await previewDistances(page, source.image_src, [aroundCentre, towardsAnchor])
  expect(onCentre).toBeLessThan(onAnchor)

  // A zoomed save keeps the pin on its place in the photo and its mode. At 2×
  // the frame is 130 × 87 at column 0.75 × 162 = 122; the pin, column 219, is
  // 75 % across it, so the server cuts the other sizes from the saved file
  // where the editor showed them.
  const zoomed = await openOnPositionImage(page, uploaded, { x: 75, y: 0 }, 'posfocalzoom')
  const slider = page.locator('#image-editor-zoom')
  await slider.fill('2')
  await slider.dispatchEvent('input')
  await expect(page.locator('#image-editor-zoom-value')).toHaveText('2.00x')
  const replaced = page.waitForResponse(r => r.url().includes('/replace_crop'))
  await page.locator('#image-editor-save-replace').click()
  expect((await replaced).ok()).toBeTruthy()

  expect(await reopenAfterSave(page)).toMatchObject({
    image_id: zoomed.id, image_width: 130, image_height: 87, focal_x: 75, focal_y: 0, focal_mode: 'position',
  })
})
