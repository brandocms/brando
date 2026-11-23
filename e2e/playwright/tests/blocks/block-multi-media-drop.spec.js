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

  // Moved to another row, the entry mounts again, and its field's element
  // with it: what the field was told by the drop goes with the upload, not
  // with the element.
  test('an entry moved to another row while its upload waits goes when the upload is cancelled', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 2200 })
    await createPage(page, 'Media drop moved', group, 'Image Row')
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: group }).click()
    await page.getByRole('button', { name: 'Image Row', exact: true }).click()
    await syncLV(page)
    const [first, second] = [rows(page).nth(0), rows(page).nth(1)]

    await page.evaluate(() => { window.BrandoUploads._hook._maxTransfers = 0 })
    await drop(page, rowBlock(first), [['image.jpg', 'image/jpeg']])
    await expect(entries(first)).toHaveCount(1)
    const queued = page.locator('.upload-item.status-queued').filter({ hasText: 'image.jpg' })
    await expect(queued).toBeVisible()

    const fieldBefore = await field(entries(first).first()).elementHandle()
    const handle = await entries(first).first().locator('.sort-handle').first().boundingBox()
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2)
    await page.mouse.down()
    // the hold Sortable takes before a drag starts (block-multi-move-between-rows.spec.js)
    await page.waitForTimeout(100)
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2 + 10, { steps: 2 })
    await expect(second.locator('.block-children')).toHaveClass(/is-drop-target/)
    const target = await second.locator('.block-children').boundingBox()
    await page.mouse.move(target.x + target.width / 2, target.y + target.height / 2, { steps: 20 })
    await expect(second.locator('.block-children > .is-sorting')).toHaveCount(1)
    await page.mouse.up()
    await syncLV(page)
    await expect(entries(second)).toHaveCount(1)
    await expect(entries(first)).toHaveCount(0)
    // the field is another element now
    expect(await fieldBefore.evaluate(el => el.isConnected)).toBe(false)

    await queued.getByRole('button', { name: 'Cancel' }).click()
    await expect(entries(second)).toHaveCount(0)
  })

  test('a multi block without media_drop shows no drop zone', async ({ page }) => {
    await createPage(page, 'Media drop none', '06 COPY PASTE TEST', 'Team Section')
    await expect(rows(page)).toHaveCount(1)
    await expect(page.locator('.block-media-drop')).toHaveCount(0)
  })
})
