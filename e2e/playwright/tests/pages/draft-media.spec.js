import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

const mediaState = async (page, schema, id = 'new') => {
  const response = await page.request.post('/e2e/drafts/media-state', { data: { schema, entry_id: String(id) } })
  expect(response.ok()).toBeTruthy()
  return response.json()
}

const waitForCopy = async (page, schema, id, predicate) => {
  await expect.poll(async () => (await mediaState(page, schema, id)).drafts.some(predicate), { timeout: 30000 }).toBe(true)
  await expect(page.getByTestId('draft-status')).toContainText('Recovery copy saved at')
}

const screenshot = async (page, testInfo, name) => {
  await page.evaluate(() => window.scrollTo({ top: 0, behavior: 'instant' }))
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBe(0)
  await expect(page.getByTestId('draft-status')).toContainText('Recovery copy saved at')
  await page.screenshot({ path: testInfo.outputPath(name), fullPage: true, animations: 'disabled' })
}

const restore = async page => {
  await page.reload()
  await page.getByRole('button', { name: 'Review recovery copy', exact: true }).click()
  await page.getByRole('button', { name: 'Restore recovery copy', exact: true }).click()
  await expect(page.getByTestId('draft-panel')).toHaveCount(0)
  await syncLV(page)
}

const openProject = async page => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByText('Published', { exact: true }).click()
  await page.getByRole('textbox', { name: 'Name', exact: true }).fill('Recovery client')
  await page.getByRole('textbox', { name: 'Slug', exact: true }).fill('recovery-client')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/projects\/clients$/)
  await page.goto('/admin/projects/projects')
  await page.getByRole('link', { name: 'Test Project Gamma' }).click()
  await syncLV(page)
  const path = new URL(page.url()).pathname
  const id = path.split('/').at(-1)
  await page.locator('#project_client_id-field-base').getByRole('button', { name: 'Select', exact: true }).click()
  await page.getByRole('button', { name: 'Recovery client', exact: true }).click()
  await page.locator('.tiptap-wrapper [contenteditable="true"]').fill('A project for media recovery testing.')
  return { path, id }
}

const saveProject = async (page, path) => {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/projects\/projects$/, { timeout: 30000 })
  await page.goto(path)
  await syncLV(page)
}

const projectMediaField = (page, type) => {
  const field = { image: 'listing_image', file: 'cover_file', video: 'cover_video' }[type]
  return page.locator(`#project_${field}-media`)
}
const blockMediaVar = (page, type) => page.locator(`.media-field[data-kind="block_var"][id$="-${type}-media"]`)

const uploadField = async (page, type, file) => {
  const field = projectMediaField(page, type)
  const previous = await field.getAttribute('data-asset-id')
  await field.locator('input[type="file"]').setInputFiles(file)
  if (type === 'image') await confirmUploadFolder(page)
  await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  if (previous) await expect(field).not.toHaveAttribute('data-asset-id', previous, { timeout: 30000 })
  if (type === 'image') await expect(field.locator('img')).toBeVisible({ timeout: 20000 })
  await expect(field.getByRole('button', { name: 'Configure', exact: true })).toBeVisible()
}

const fields = ['listing_image_id', 'cover_file_id', 'cover_video_id']
const fieldIds = async page => Object.fromEntries(await Promise.all(fields.map(async field => [field, Number(await page.locator(`input[name="project[${field}]"]`).inputValue()) || null])))
const matchesFields = (value, expected) => fields.every(field => value[field] === expected[field])

const createPage = async (page, title) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
}

const addBlock = async (page, name, category = '05 LIVE PREVIEW TEST') => {
  await page.getByRole('button', { name: 'Add block' }).last().click()
  await page.getByRole('button', { name: category }).click()
  await page.getByRole('button', { name, exact: true }).click()
  await syncLV(page)
}

const savePage = async (page, title) => {
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
  await page.getByRole('link', { name: `${title}`, exact: true }).click()
  await syncLV(page)
  return new URL(page.url()).pathname.split('/').at(-1)
}

test.describe('Media in entry recovery copies', () => {
  test.setTimeout(180000)
  test.beforeEach(async ({ page }) => { page.setDefaultTimeout(15000) })

  test('idle forms send no captures, edits reuse one row, and Save leaves only a closed marker', async ({ page }) => {
    const captures = []
    page.on('websocket', socket => socket.on('framesent', ({ payload }) => {
      const frame = JSON.parse(String(payload))
      if (frame[4]?.event === 'draft_capture') captures.push(frame[4].value)
    }))
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await expect(page.getByTestId('draft-status')).toHaveText('No unsaved changes in this editor')
    // Observe longer than the removed 15-second polling interval.
    await page.waitForTimeout(16000)
    expect(captures).toHaveLength(0)
    expect((await mediaState(page, 'page')).storage).toHaveLength(0)

    await page.locator('#page_title').fill('One working copy')
    await page.getByLabel('URI').fill('one-working-copy')
    await waitForCopy(page, 'page', 'new', copy => copy.main.title === 'One working copy')
    const [first] = (await mediaState(page, 'page')).storage
    for (const title of ['Revised working copy', 'Finished working copy']) {
      await page.locator('#page_title').fill(title)
      await waitForCopy(page, 'page', 'new', copy => copy.main.title === title)
      const state = await mediaState(page, 'page')
      expect(state.storage).toHaveLength(1)
      expect(state.storage[0].id).toBe(first.id)
    }
    const captureCount = captures.length
    await page.waitForTimeout(16000)
    expect(captures).toHaveLength(captureCount)

    const id = await savePage(page, 'Finished working copy')
    const saved = await mediaState(page, 'page', id)
    expect(saved.drafts).toHaveLength(0)
    expect(saved.storage).toEqual([expect.objectContaining({ id: first.id, empty: true, resolved: true })])
    await page.reload()
    await expect(page.locator('#page_title')).toHaveValue('Finished working copy')
    await expect(page.getByTestId('draft-notice')).toHaveCount(0)
  })

  test('saving new content permanently retires recovery copies matching the previous saved version', async ({ page }) => {
    await createPage(page, 'Previous saved content')
    const id = await savePage(page, 'Previous saved content')
    // Insert after mount to also cover copies missed by initial reconciliation.
    expect((await page.request.post('/e2e/drafts/legacy-copies', { data: { entry_id: id } })).ok()).toBeTruthy()
    expect((await mediaState(page, 'page', id)).drafts).toHaveLength(14)

    for (const title of ['New saved content', 'Saved again']) {
      await page.locator('#page_title').fill(title)
      await savePage(page, title)
      await expect(page.getByTestId('draft-notice')).toHaveCount(0)
      await expect(page.getByRole('button', { name: /^Recovery copies/ })).toHaveCount(0)
      await page.reload()
      await expect(page.locator('#page_title')).toHaveValue(title)
      await expect(page.getByTestId('draft-status')).toHaveText('No unsaved changes in this editor', { timeout: 25000 })
      await expect(page.getByTestId('draft-notice')).toHaveCount(0)
      const state = await mediaState(page, 'page', id)
      expect(state.drafts).toHaveLength(0)
      expect(state.storage.every(copy => copy.empty && copy.resolved)).toBe(true)
    }
  })

  test('a rejected Save retains the full recovery payload', async ({ page }) => {
    await createPage(page, 'Work surviving a rejected save')
    await page.getByText('Published', { exact: true }).click()
    await page.getByLabel('URI').fill('')
    await waitForCopy(page, 'page', 'new', copy => copy.main.uri === '')
    await page.getByTestId('submit').click()
    await expect(page.locator('#page_uri-error')).toContainText("can't be blank")
    const state = await mediaState(page, 'page')
    expect(state.drafts[0].main.title).toBe('Work surviving a rejected save')
    expect(state.storage).toEqual([expect.objectContaining({ empty: false, resolved: false })])
    await page.reload()
    await expect(page.getByTestId('draft-notice')).toBeVisible()
  })

  test('opening legacy content resolves no-op copies and does not create another copy on capture or reload', async ({ page }) => {
    const title = 'Unchanged legacy gallery'
    await createPage(page, title)
    await addBlock(page, 'Gallery with Controls')
    const gallery = page.locator('.gallery-block')
    await gallery.locator('.file-input').setInputFiles(['./fixtures/image.jpg'])
    await confirmUploadFolder(page)
    await expect(gallery.locator('.gallery-object')).toHaveCount(1, { timeout: 30000 })
    const id = await savePage(page, title)
    expect((await page.request.post('/e2e/drafts/legacy-copies', { data: { entry_id: id } })).ok()).toBeTruthy()
    expect((await mediaState(page, 'page', id)).drafts).toHaveLength(14)

    for (let session = 0; session < 2; session++) {
      await page.reload()
      await syncLV(page)
      await expect(page.getByTestId('draft-status')).toHaveText('No unsaved changes in this editor', { timeout: 25000 })
      await expect(page.getByTestId('draft-notice')).toHaveCount(0)
      await expect(page.getByRole('button', { name: /^Recovery copies/ })).toHaveCount(0)
      expect((await mediaState(page, 'page', id)).drafts).toHaveLength(0)
    }

    // A real edit must still be offered after retiring the unchanged originals.
    await page.locator('#page_title').fill('An actual unsaved edit')
    await waitForCopy(page, 'page', id, copy => copy.main.title === 'An actual unsaved edit')
    await page.reload()
    await page.getByRole('button', { name: 'Review recovery copy', exact: true }).click()
    await expect(page.locator('.draft-copy-table tbody tr')).toHaveCount(1)
    await page.getByRole('button', { name: 'Restore recovery copy', exact: true }).click()
    await expect(page.locator('#page_title')).toHaveValue('An actual unsaved edit')
    await expect(gallery.locator('.gallery-object')).toHaveCount(1)
    await savePage(page, 'An actual unsaved edit')
    await expect(page.getByTestId('draft-notice')).toHaveCount(0)
    await page.reload()
    await expect(page.locator('#page_title')).toHaveValue('An actual unsaved edit')
    await expect(page.getByTestId('draft-status')).toHaveText('No unsaved changes in this editor', { timeout: 25000 })
    expect((await mediaState(page, 'page', id)).drafts).toHaveLength(0)
  })

  test('image, file and video fields recover selections, replacements and resets without duplicating assets', async ({ page }, testInfo) => {
    const { path, id } = await openProject(page)
    for (const [type, file] of [['image', 'image.jpg'], ['file', 'test.pdf'], ['video', 'video.mp4']]) {
      await uploadField(page, type, `./fixtures/${file}`)
    }
    const initial = await fieldIds(page)
    expect(Object.values(initial).every(Boolean)).toBe(true)
    await waitForCopy(page, 'project', id, copy => matchesFields(copy.main, initial))
    let counts = (await mediaState(page, 'project', id)).counts
    await restore(page)
    expect(await fieldIds(page)).toEqual(initial)
    for (const type of ['image', 'file', 'video']) await expect(projectMediaField(page, type)).toHaveAttribute('data-asset-id', /\d+/)
    await screenshot(page, testInfo, 'recovery-media-fields.png')
    await saveProject(page, path)
    let state = await mediaState(page, 'project', id)
    expect(matchesFields(state.entry, initial)).toBe(true)
    expect(state.counts).toEqual(counts)

    for (const [type, file] of [['image', 'image2.jpg'], ['file', 'test.pdf'], ['video', 'video.mp4']]) {
      await uploadField(page, type, `./fixtures/${file}`)
    }
    const replacement = await fieldIds(page)
    for (const field of fields) expect(replacement[field]).not.toBe(initial[field])
    await waitForCopy(page, 'project', id, copy => matchesFields(copy.main, replacement))
    counts = (await mediaState(page, 'project', id)).counts
    await restore(page)
    expect(await fieldIds(page)).toEqual(replacement)
    await saveProject(page, path)
    state = await mediaState(page, 'project', id)
    expect(matchesFields(state.entry, replacement)).toBe(true)
    expect(state.counts).toEqual(counts)

    for (const type of ['image', 'file', 'video']) {
      await projectMediaField(page, type).getByRole('button', { name: 'Configure', exact: true }).click()
      const drawer = page.locator(`#${type}-drawer`)
      if (type === 'image') await drawer.getByLabel('More image actions', { exact: true }).click()
      await drawer.getByRole('button', { name: type === 'video' ? 'Reset video field' : 'Remove', exact: true }).click()
      await expect(page.locator(`#${type}-drawer`)).toBeHidden()
    }
    const cleared = Object.fromEntries(fields.map(field => [field, null]))
    await waitForCopy(page, 'project', id, copy => matchesFields(copy.main, cleared))
    await restore(page)
    for (const type of ['image', 'file', 'video']) await expect(projectMediaField(page, type).getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
    expect(await fieldIds(page)).toEqual(cleared)
    await saveProject(page, path)
    state = await mediaState(page, 'project', id)
    expect(matchesFields(state.entry, cleared)).toBe(true)
    expect(state.counts).toEqual(counts)
  })

  test('a mixed gallery field recovers its order and later deletions', async ({ page }, testInfo) => {
    const { path, id } = await openProject(page)
    const gallery = page.locator('.gallery-input')
    const chooser = page.waitForEvent('filechooser')
    await gallery.getByRole('button', { name: 'Upload media', exact: true }).click()
    await (await chooser).setFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
    await confirmUploadFolder(page)
    await expect(gallery.locator('.gallery-object')).toHaveCount(2, { timeout: 30000 })
    await gallery.locator('input[type="file"]').setInputFiles('./fixtures/video.mp4')
    await expect(gallery.locator('.gallery-object')).toHaveCount(3, { timeout: 30000 })
    const objects = gallery.locator('.gallery-object')
    await gallery.scrollIntoViewIfNeeded()
    await page.mouse.wheel(0, 350)
    const previousOrder = await objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))
    const target = await objects.first().boundingBox()
    const source = await objects.last().boundingBox()
    await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2)
    await page.mouse.down()
    await page.mouse.move(source.x + source.width / 2 + 10, source.y + source.height / 2, { steps: 4 })
    await expect(page.locator('.sortable-fallback')).toBeVisible()
    await page.mouse.move(target.x + 5, target.y + target.height / 2, { steps: 20 })
    await page.mouse.up()
    await expect(objects).toHaveCount(3)
    const order = await objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))
    expect(order).not.toEqual(previousOrder)
    await page.getByLabel('Title', { exact: true }).blur()
    await syncLV(page)
    const rows = copy => copy.main.project_gallery?.gallery_objects || []
    await waitForCopy(page, 'project', id, copy => JSON.stringify(rows(copy).map(row => row.image_id || row.video_id)) === JSON.stringify(order))
    const counts = (await mediaState(page, 'project', id)).counts
    await restore(page)
    await expect(objects).toHaveCount(3)
    await expect(objects.locator('img')).toHaveCount(2)
    await screenshot(page, testInfo, 'recovery-gallery-field.png')
    expect(await objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))).toEqual(order)
    await saveProject(page, path)
    let state = await mediaState(page, 'project', id)
    const persisted = state.entry.project_gallery.gallery_objects
    expect(persisted.filter(row => row.image_id)).toHaveLength(2)
    expect(persisted.filter(row => row.video_id)).toHaveLength(1)
    expect(persisted.map(row => row.image_id || row.video_id)).toEqual(order)
    expect(state.counts.images).toBe(counts.images)
    expect(state.counts.videos).toBe(counts.videos)
    const galleryCount = state.counts.galleries
    await objects.first().locator('.delete-object').click()
    await expect(objects).toHaveCount(2)
    const remaining = await objects.evaluateAll(nodes => nodes.map(node => Number(node.dataset.id)))
    await waitForCopy(page, 'project', id, copy => rows(copy).length === 2)
    await restore(page)
    await expect(objects).toHaveCount(2)
    await saveProject(page, path)
    state = await mediaState(page, 'project', id)
    expect(state.entry.project_gallery.gallery_objects.map(row => row.image_id || row.video_id)).toEqual(remaining)
    expect(state.counts.galleries).toBe(galleryCount)
  })

  test('gallery blocks retain mixed media and deletions through draft restore and save', async ({ page }, testInfo) => {
    const title = 'Recovered media gallery'
    await createPage(page, title)
    await addBlock(page, 'Gallery with Controls')
    const gallery = page.locator('.gallery-block')
    await gallery.locator('.file-input').setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
    await confirmUploadFolder(page)
    await expect(gallery.locator('.gallery-object')).toHaveCount(2, { timeout: 30000 })
    await gallery.getByRole('button', { name: 'Browse videos', exact: true }).click()
    await page.locator('.video-picker__video', { hasText: 'Test Video' }).first().click()
    await page.locator('#video-picker').getByRole('button', { name: 'Close', exact: true }).click()
    await expect(gallery.locator('.gallery-object')).toHaveCount(3)
    const rows = copy => copy.blocks.blocks?.[0]?.block.refs?.find(ref => ref.name === 'gallery')?.gallery?.gallery_objects || []
    await waitForCopy(page, 'page', 'new', copy => rows(copy).length === 3)
    const counts = (await mediaState(page, 'page')).counts
    await restore(page)
    await expect(gallery.locator('.gallery-object')).toHaveCount(3)
    await screenshot(page, testInfo, 'recovery-gallery-block.png')
    const id = await savePage(page, title)
    const before = await mediaState(page, 'page', id)
    expect(before.counts.images).toBe(counts.images)
    expect(before.counts.videos).toBe(counts.videos)
    await gallery.locator('.gallery-object .delete-x').first().click()
    await expect(gallery.locator('.gallery-object')).toHaveCount(2)
    await waitForCopy(page, 'page', id, copy => rows(copy).length === 2)
    await restore(page)
    await expect(gallery.locator('.gallery-object')).toHaveCount(2)
    await savePage(page, title)
    const after = await mediaState(page, 'page', id)
    expect(after.entry.entry_blocks[0].block.refs[0].gallery.gallery_objects).toHaveLength(2)
    expect(after.counts).toEqual(before.counts)
  })

  test('picture and video refs plus image and file vars recover, save and reset', async ({ page }, testInfo) => {
    const title = 'Recovered media refs and vars'
    await createPage(page, title)
    await addBlock(page, 'Single Image with Caption')
    const picture = page.locator('.picture-block')
    await picture.locator('.file-input').last().setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await expect(picture.locator('.media-field--block:visible img')).toBeVisible({ timeout: 30000 })
    await addBlock(page, 'Video Player')
    await page.locator('.video-block .media-field:visible').getByRole('button', { name: 'Browse library', exact: true }).click()
    await page.locator('.video-picker__video', { hasText: 'Test Video' }).first().click()
    await expect(page.locator('.video-block .media-field:visible')).toContainText('Test Video')
    await addBlock(page, 'Image and File Vars', '07 VAR UPLOAD TEST')
    for (const [type, file] of [['image', 'image2.jpg'], ['file', 'test.pdf']]) {
      const field = blockMediaVar(page, type)
      const chooser = page.waitForEvent('filechooser')
      await field.getByRole('button', { name: 'Upload', exact: true }).click()
      await (await chooser).setFiles(`./fixtures/${file}`)
      if (type === 'image') await confirmUploadFolder(page)
      await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
      if (type === 'image') await expect(field.locator('img')).toBeVisible({ timeout: 30000 })
    }
    const media = copy => {
      const blocks = (copy.blocks.blocks || []).map(row => row.block)
      const refs = blocks.flatMap(block => block.refs || [])
      const vars = blocks.flatMap(block => block.vars || [])
      return [refs.find(ref => ref.image_id)?.image_id, refs.find(ref => ref.video_id)?.video_id,
        vars.find(variable => variable.type === 'image')?.image_id, vars.find(variable => variable.type === 'file')?.file_id]
    }
    await waitForCopy(page, 'page', 'new', copy => media(copy).every(Boolean))
    const counts = (await mediaState(page, 'page')).counts
    await restore(page)
    await expect(picture.locator('.media-field--block:visible img')).toBeVisible()
    await expect(page.locator('.video-block .media-field:visible')).toContainText('Test Video')
    await expect(blockMediaVar(page, 'image')).toHaveAttribute('data-asset-id', /\d+/)
    await expect(blockMediaVar(page, 'file')).toHaveAttribute('data-asset-id', /\d+/)
    await screenshot(page, testInfo, 'recovery-media-refs-vars.png')
    const id = await savePage(page, title)
    expect((await mediaState(page, 'page', id)).counts).toEqual(counts)
    for (const type of ['image', 'file']) {
      await blockMediaVar(page, type).getByRole('button', { name: 'Configure', exact: true }).click()
      const modal = page.locator(`[id$="${type}-config"]:visible`)
      await modal.getByRole('button', { name: 'Remove', exact: true }).click()
      await modal.getByRole('button', { name: 'Done', exact: true }).click()
    }
    await waitForCopy(page, 'page', id, copy => media(copy).slice(0, 2).every(Boolean) && media(copy).slice(2).every(value => !value))
    await restore(page)
    for (const type of ['image', 'file']) await expect(blockMediaVar(page, type).getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
    await savePage(page, title)
    const state = await mediaState(page, 'page', id)
    const vars = state.entry.entry_blocks.flatMap(row => row.block.vars)
    expect(vars.find(variable => variable.type === 'image').image_id).toBeNull()
    expect(vars.find(variable => variable.type === 'file').file_id).toBeNull()
    expect(state.counts).toEqual(counts)
  })


  test('entry-level image, file and video variables recover and persist', async ({ page }) => {
    const title = 'Recovered entry media variables'
    await createPage(page, title)
    await page.getByRole('button', { name: 'Advanced', exact: true }).click()
    for (const [index, type] of ['image', 'file', 'video'].entries()) {
      await page.getByRole('button', { name: 'Add entry', exact: true }).click()
      const entry = page.locator('.subform-entry').nth(index)
      await entry.locator('.variable-header').click()
      await entry.locator('.field-wrapper:has-text("Type") .button-edit').click()
      await entry.getByRole('button', { name: type[0].toUpperCase() + type.slice(1), exact: true }).click()
      await syncLV(page)
      await expect(entry.locator('input[name$="[type]"]')).toHaveValue(type)
      await entry.getByLabel('Key', { exact: true }).fill(`recovery_${type}`)
      await entry.getByLabel('Key', { exact: true }).blur()
      await syncLV(page)
      const field = entry.locator('.media-field[id$="-media"]')
      if (type === 'video') {
        await field.getByRole('button', { name: 'Browse library', exact: true }).click()
        await page.locator('.video-picker__video', { hasText: 'Test Video' }).first().click()
        await expect(page.locator('#video-picker')).toBeHidden()
        await expect(field).toContainText('Test Video')
      } else {
        await field.locator('input[type="file"]').setInputFiles(type === 'image' ? './fixtures/image.jpg' : './fixtures/test.pdf')
        if (type === 'image') await confirmUploadFolder(page)
      }
      await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    }
    await waitForCopy(page, 'page', 'new', copy => ['image', 'file', 'video'].every(type =>
      copy.main.vars?.find(variable => variable.key === `recovery_${type}`)?.[`${type}_id`]))
    const counts = (await mediaState(page, 'page')).counts
    await restore(page)
    await page.getByRole('button', { name: 'Advanced', exact: true }).click()
    for (const [index, type] of ['image', 'file', 'video'].entries()) {
      const entry = page.locator('.subform-entry').nth(index)
      if (!(await entry.getByLabel('Key', { exact: true }).isVisible())) await entry.locator('.variable-header').click()
      await expect(entry.locator('.media-field[id$="-media"]')).toHaveAttribute('data-asset-id', /\d+/)
    }
    const id = await savePage(page, title)
    const state = await mediaState(page, 'page', id)
    for (const type of ['image', 'file', 'video']) expect(state.entry.vars.find(variable => variable.key === `recovery_${type}`)[`${type}_id`]).toBeTruthy()
    expect(state.counts).toEqual(counts)
  })

})
