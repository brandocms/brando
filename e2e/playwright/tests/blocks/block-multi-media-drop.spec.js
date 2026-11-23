import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import fs from 'node:fs'

// A multi module with `media_drop` (an Image Row, whose entries are Image
// Cards with a media ref) makes one entry per image or video dropped on its
// blocks, in the order dropped, each with its file in that ref.
test.describe('Multi blocks: dropping media', () => {
  test.setTimeout(120000)

  const rows = page => page.locator('[data-module-multi="true"]')
  const entries = row => row.locator('.block-children > [data-uid]')
  const field = entry => entry.locator('.media-field--block:visible').first()

  const group = 'Media drop rows'

  const factory = async (page, attributes) => {
    const response = await page.request.post('/__e2e/db/factory', {
      data: { schema: 'Brando.Content.Module', creator_id: 1, fields: ['id'], attributes },
    })
    expect(response.ok(), await response.text()).toBeTruthy()
    return (await response.json()).id
  }

  // The Image Row and its Image Card, in the test's sandbox
  test.beforeEach(async ({ page }) => {
    const module = (name, extra) => ({
      name: { en: name, no: name }, namespace: { en: group, no: group }, help_text: { en: name },
      class: name.toLowerCase().replace(' ', '-'), type: 'liquid', vars: [], datasource: false, ...extra,
    })

    const row = await factory(page, module('Image Row', {
      uid: 'e2e-image-row', code: '<section>{{ content }}</section>', refs: [], multi: true,
      media_drop_child: 'e2e-image-card', media_drop_ref: 'visual',
    }))

    await factory(page, module('Image Card', {
      uid: 'e2e-image-card', parent_id: row, multi: false,
      code: '<figure>{% ref refs.visual %}</figure>',
      refs: [{
        name: 'visual', description: 'Image or video', uid: 'e2e-image-card-visual',
        data: { type: 'media', data: { available_blocks: ['picture', 'video'], template_picture: {}, template_video: {} } },
      }],
    }))
  })

  const createPage = async (page, title, group, module) => {
    await page.setViewportSize({ width: 1440, height: 1400 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: group }).click()
    await page.getByRole('button', { name: module, exact: true }).click()
    await syncLV(page)
  }

  // Files dropped on `target` as the browser drops them: `[name, type]`, or
  // `[name, type, fixture]` for a fixture's bytes under another name
  const drop = async (page, target, files) => {
    const payload = files.map(([name, type, fixture = name]) => ({
      name, type, bytes: [...fs.readFileSync(`./fixtures/${fixture}`)],
    }))
    const transfer = await page.evaluateHandle(files => {
      const transfer = new DataTransfer()
      for (const { name, type, bytes } of files) transfer.items.add(new File([new Uint8Array(bytes)], name, { type }))
      return transfer
    }, payload)
    await target.dispatchEvent('dragenter', { dataTransfer: transfer })
    await target.dispatchEvent('dragover', { dataTransfer: transfer })
    await target.dispatchEvent('drop', { dataTransfer: transfer })
    await transfer.dispose()
  }

  // The row's own block element, which takes a drop anywhere on it
  const rowBlock = row => row.locator('.block').first()

  // A second row of `module` below the first
  const addRow = async (page, module) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: group }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText(group)
    await page.getByRole('button', { name: module, exact: true }).click()
    await syncLV(page)
    await expect(rows(page).last()).toContainText(module)
  }

  // `entry` dragged by its handle into `row`'s children
  const moveTo = async (page, entry, row) => {
    const handle = await entry.locator('.sort-handle').first().boundingBox()
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2)
    await page.mouse.down()
    // the hold Sortable takes before a drag starts (block-multi-move-between-rows.spec.js)
    await page.waitForTimeout(100)
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2 + 10, { steps: 2 })
    await expect(row.locator('.block-children')).toHaveClass(/is-drop-target/)
    const target = await row.locator('.block-children').boundingBox()
    await page.mouse.move(target.x + target.width / 2, target.y + target.height / 2, { steps: 20 })
    await expect(row.locator('.block-children > .is-sorting')).toHaveCount(1)
    await page.mouse.up()
    await syncLV(page)
  }

  const kinds = row =>
    entries(row).evaluateAll(items =>
      items.map(item => (item.querySelector('.video-block') ? 'video' : item.querySelector('.picture-block') ? 'picture' : null))
    )

  const assetIds = row =>
    entries(row).evaluateAll(items =>
      items.map(item => item.querySelector('.media-field--block[data-asset-id]')?.dataset.assetId || null)
    )

  test('two images and a video become three entries in order, saved with their media', async ({ page }) => {
    const title = 'Media drop row'
    await createPage(page, title, group, 'Image Row')
    const row = rows(page).first()
    await expect(row.locator('.block-media-drop')).toBeVisible()

    await drop(page, rowBlock(row), [
      ['image.jpg', 'image/jpeg'],
      ['video.mp4', 'video/mp4'],
      ['image2.jpg', 'image/jpeg'],
    ])

    await expect(entries(row)).toHaveCount(3)
    expect(await kinds(row)).toEqual(['picture', 'video', 'picture'])
    for (const entry of await entries(row).all()) {
      await expect(field(entry)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    }

    // A file dropped on an entry's own field fills only that field
    const first = entries(row).first()
    const before = await field(first).getAttribute('data-asset-id')
    await drop(page, field(first), [['image2.jpg', 'image/jpeg']])
    await expect(field(first)).not.toHaveAttribute('data-asset-id', before, { timeout: 30000 })
    await expect(entries(row)).toHaveCount(3)

    const ids = await assetIds(row)

    await page.getByTestId('submit').click()
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 30000 })
    await page.getByRole('link', { name: title, exact: true }).click()
    await syncLV(page)

    const saved = rows(page).first()
    await expect(entries(saved)).toHaveCount(3)
    expect(await kinds(saved)).toEqual(['picture', 'video', 'picture'])
    expect(await assetIds(saved)).toEqual(ids)
  })

  test('a file the ref does not take makes no entry and is reported', async ({ page }) => {
    await createPage(page, 'Media drop refused', group, 'Image Row')
    const row = rows(page).first()

    await drop(page, row.locator('.block-media-drop'), [
      ['test.pdf', 'application/pdf'],
      ['image.jpg', 'image/jpeg'],
    ])

    await expect(page.getByRole('dialog').filter({ hasText: 'test.pdf' })).toBeVisible()
    await expect(entries(row)).toHaveCount(1)
    await expect(field(entries(row).first())).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  })

  // The upload manager takes an image by its extension, whatever its type says
  test('an image with an extension the upload refuses makes no entry and is reported', async ({ page }) => {
    await createPage(page, 'Media drop extension', group, 'Image Row')
    const row = rows(page).first()

    await drop(page, rowBlock(row), [['photo.bin', 'image/jpeg', 'image.jpg']])

    await expect(page.getByRole('dialog').filter({ hasText: 'photo.bin' })).toBeVisible()
    await expect(entries(row)).toHaveCount(0)
  })

  test('an entry whose upload is cancelled goes again', async ({ page }) => {
    await createPage(page, 'Media drop cancelled', group, 'Image Row')
    const row = rows(page).first()

    // Hold the manager's transfers, so the upload is still queued when cancelled
    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    await drop(page, rowBlock(row), [['image.jpg', 'image/jpeg'], ['image2.jpg', 'image/jpeg']])
    await expect(entries(row)).toHaveCount(2)

    const queued = page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })
    await queued.getByRole('button', { name: 'Cancel' }).click()
    await expect(entries(row)).toHaveCount(1)

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 3; window.BrandoUploads._hook.pumpTransfers() })
    await expect(field(entries(row).first())).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  })

  // The drop zone the file was dropped on can be gone by the time the
  // entry's field is there to take the file: the entry still goes when the
  // upload does.
  test('an entry whose drop zone left the page before the handover goes when its upload is cancelled', async ({ page }) => {
    await createPage(page, 'Media drop zone gone', group, 'Image Row')
    const row = rows(page).first()

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    // after the drop zone has taken the drop, before its reply comes back
    await rowBlock(row).evaluate(block => block.addEventListener('drop', () => {
      block.querySelector('[phx-hook="Brando.MediaDrop"]').remove()
    }))
    await drop(page, rowBlock(row), [['image.jpg', 'image/jpeg']])
    await expect(entries(row)).toHaveCount(1)

    const queued = page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })
    await queued.getByRole('button', { name: 'Cancel' }).click()
    await expect(entries(row)).toHaveCount(0)
  })

  // Moved to another row, the entry mounts again, and its field's element
  // with it: what the field was told by the drop goes with the upload, not
  // with the element.
  test('an entry moved to another row while its upload waits goes when the upload is cancelled', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 2200 })
    await createPage(page, 'Media drop moved', group, 'Image Row')
    await addRow(page, 'Image Row')
    const [first, second] = [rows(page).nth(0), rows(page).nth(1)]

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    await drop(page, rowBlock(first), [['image.jpg', 'image/jpeg']])
    await expect(entries(first)).toHaveCount(1)
    const queued = page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })
    await expect(queued).toBeVisible()

    const fieldBefore = await field(entries(first).first()).elementHandle()
    await moveTo(page, entries(first).first(), second)
    await expect(entries(second)).toHaveCount(1)
    await expect(entries(first)).toHaveCount(0)
    // the field is another element now
    expect(await fieldBefore.evaluate(el => el.isConnected)).toBe(false)

    await queued.getByRole('button', { name: 'Cancel' }).click()
    await expect(entries(second)).toHaveCount(0)
  })

  // The drop hands its file's upload to the field. A file dropped straight
  // on the field meanwhile is the field's own: its failure leaves the entry
  // to the dropped file's upload.
  test('a file dropped on the field while the dropped file waits leaves the entry to that upload', async ({ page }) => {
    await createPage(page, 'Media drop second file', group, 'Image Row')
    const row = rows(page).first()

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    await drop(page, rowBlock(row), [['image.jpg', 'image/jpeg']])
    await expect(entries(row)).toHaveCount(1)
    const entry = entries(row).first()
    await expect(page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })).toBeVisible()

    // refused by the upload manager at once
    await drop(page, field(entry), [['photo.bin', 'image/jpeg', 'image.jpg']])
    await expect(field(entry).locator('.media-field-progress')).toHaveAttribute('data-state', 'error')
    await syncLV(page)
    await expect(page.locator('dialog.admin-dialog[open]')).toHaveCount(0)

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 3; window.BrandoUploads._hook.pumpTransfers() })
    await expect(entries(row)).toHaveCount(1)
    await expect(field(entry)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  })

  // The folder question ("Change") holds no files: a dropped file uploads
  // whatever the editor answers, and settles its entry once. A later upload
  // into the same field that fails is that upload's own.
  test('a folder choice cancelled while a dropped file waits leaves the entry to its upload', async ({ page }) => {
    await createPage(page, 'Media drop folder cancelled', group, 'Image Row')
    const row = rows(page).first()

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    await drop(page, rowBlock(row), [['image.jpg', 'image/jpeg']])
    await expect(entries(row)).toHaveCount(1)
    const entry = entries(row).first()
    await expect(page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })).toBeVisible()

    await field(entry).getByRole('button', { name: 'Change upload folder', exact: true }).click()
    const picker = page.locator('#image-picker')
    await picker.getByRole('button', { name: 'Cancel', exact: true }).click()
    await expect(picker).not.toBeVisible()

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 3; window.BrandoUploads._hook.pumpTransfers() })
    await expect(field(entry)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })

    // Emptied, the field would settle nothing pending as a success: the
    // upload refused next is the field's own, not the drop's
    await field(entry).getByRole('button', { name: 'Remove', exact: true }).click()
    await expect(field(entry)).not.toHaveAttribute('data-asset-id', /./)
    await drop(page, field(entry), [['photo.bin', 'image/jpeg', 'image.jpg']])
    await expect(field(entry).locator('.media-field-progress')).toHaveAttribute('data-state', 'error')
    await expect(page.locator('.upload-item.status-error')).toHaveCount(1)
    await syncLV(page)

    await expect(entries(row)).toHaveCount(1)
    await expect(field(entry)).not.toHaveAttribute('data-asset-id', /./)
    // no alert that the dropped file's upload failed
    await expect(page.locator('dialog.admin-dialog[open]')).toHaveCount(0)
  })

  // A Video Row whose Video Card's ref uploads to its provider, the E2E
  // app's fake Bunny, which answers on its CDN hostname here
  const videoRow = async page => {
    await page.route('https://bunny-cdn.e2e.test/**', route => route.fulfill({ path: './fixtures/image.jpg', contentType: 'image/jpeg' }))
    const row = await factory(page, {
      name: { en: 'Video Row', no: 'Video Row' }, namespace: { en: group, no: group }, help_text: { en: 'Video Row' },
      class: 'video-row', type: 'liquid', vars: [], datasource: false,
      uid: 'e2e-video-row', code: '<section>{{ content }}</section>', refs: [], multi: true,
      media_drop_child: 'e2e-video-card', media_drop_ref: 'visual',
    })
    await factory(page, {
      name: { en: 'Video Card', no: 'Video Card' }, namespace: { en: group, no: group }, help_text: { en: 'Video Card' },
      class: 'video-card', type: 'liquid', vars: [], datasource: false,
      uid: 'e2e-video-card', parent_id: row, multi: false,
      code: '<figure>{% ref refs.visual %}</figure>',
      refs: [{
        name: 'visual', description: 'Video', uid: 'e2e-video-card-visual',
        data: {
          type: 'media',
          data: { available_blocks: ['video'], template_video: { config_target: 'video:E2eProject.Projects.Project:bunny_video' } },
        },
      }],
    })
  }

  // The provider's `done` settles the drop once the ref shows the video.
  // Emptied after that, the field's next failed upload is its own.
  test('a video dropped on a provider ref settles its entry when the ref takes it', async ({ page }) => {
    await videoRow(page)
    await createPage(page, 'Media drop provider', group, 'Video Row')
    const row = rows(page).first()
    await drop(page, rowBlock(row), [['video.mp4', 'video/mp4']])
    await expect(entries(row)).toHaveCount(1)
    const entry = entries(row).first()
    await expect(field(entry)).toHaveAttribute('data-video-hook-id', /uploader$/)
    await expect(field(entry)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })

    await field(entry).getByRole('button', { name: 'Remove', exact: true }).click()
    await expect(field(entry)).not.toHaveAttribute('data-asset-id', /./)
    await page.route('**/e2e/bunny/tus**', route => route.fulfill({ status: 403 }))
    await drop(page, field(entry), [['video.mp4', 'video/mp4']])
    await expect(field(entry).locator('.media-field-progress')).toHaveAttribute('data-state', 'error', { timeout: 30000 })
    await syncLV(page)

    await expect(entries(row)).toHaveCount(1)
    await expect(field(entry)).not.toHaveAttribute('data-asset-id', /./)
    // no alert that the dropped file's upload failed
    await expect(page.locator('dialog.admin-dialog[open]')).toHaveCount(0)
  })

  // Moved to another row, the entry's field mounts again, and the provider's
  // hook with it: the transfer ends there. The drop's upload failed, and
  // says so; a later upload into the field is the field's own.
  test('a video whose provider upload a move ends removes its entry, and says why', async ({ page }) => {
    await videoRow(page)
    const settled = []
    page.on('websocket', socket => socket.on('framesent', ({ payload }) => {
      const frame = JSON.parse(String(payload))
      if (frame[4]?.event === 'media_drop_settled') settled.push(frame[4].value)
    }))
    await page.setViewportSize({ width: 1440, height: 2200 })
    await createPage(page, 'Media drop provider moved', group, 'Video Row')
    await addRow(page, 'Video Row')
    const [first, second] = [rows(page).nth(0), rows(page).nth(1)]

    // The provider never answers, so the transfer is still running at the move
    await page.route('**/e2e/bunny/tus**', () => {})
    const transfer = page.waitForRequest('**/e2e/bunny/tus**')
    await drop(page, rowBlock(first), [['video.mp4', 'video/mp4']])
    await expect(entries(first)).toHaveCount(1)
    await transfer

    await moveTo(page, entries(first).first(), second)

    await expect(page.locator('dialog.admin-dialog[open]')).toHaveCount(1, { timeout: 30000 })
    // the alert for a stopped upload, not one carrying the hook's own error
    expect(settled).toEqual([expect.objectContaining({ failed: true, aborted: true })])
    await expect(entries(second)).toHaveCount(0)
    await expect(entries(first)).toHaveCount(0)
  })

  // The provider has the file, but the server cannot complete the upload:
  // the drop failed, and its entry goes as any failed drop's does
  test('a video the server cannot complete after its provider upload removes its entry', async ({ page }) => {
    await videoRow(page)
    await createPage(page, 'Media drop provider refused', group, 'Video Row')
    // A token the server never signed, as the provider hook gets it
    await page.evaluate(() => {
      window.addEventListener('phx:video_upload_url_ready', event => { event.detail.upload_token = 'forged' }, { capture: true })
    })

    const row = rows(page).first()
    await drop(page, rowBlock(row), [['video.mp4', 'video/mp4']])
    await expect(page.locator('dialog.admin-dialog[open]')).toHaveCount(1, { timeout: 30000 })
    await expect(entries(row)).toHaveCount(0)
  })

  test('a multi block without media_drop shows no drop zone', async ({ page }) => {
    await createPage(page, 'Media drop none', '06 COPY PASTE TEST', 'Team Section')
    await expect(rows(page)).toHaveCount(1)
    await expect(page.locator('.block-media-drop')).toHaveCount(0)
  })
})
