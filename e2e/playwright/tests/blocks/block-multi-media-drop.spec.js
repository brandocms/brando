import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import fs from 'node:fs'

// A multi module with `media_drop` (the seeded Image Row, whose entries are
// Image Cards with a media ref) makes one entry per image or video dropped on
// its blocks, in the order dropped, each with its file in that ref.
test.describe('Multi blocks: dropping media', () => {
  test.setTimeout(120000)

  const rows = page => page.locator('[data-module-multi="true"]')
  const entries = row => row.locator('.block-children > [data-uid]')
  const field = entry => entry.locator('.media-field--block:visible').first()

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

  // Files dropped on `target` as the browser drops them
  const drop = async (page, target, files) => {
    const payload = files.map(([name, type]) => ({ name, type, bytes: [...fs.readFileSync(`./fixtures/${name}`)] }))
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
    await createPage(page, title, '10 MEDIA DROP TEST', 'Image Row')
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
    expect(new Set(await assetIds(row)).size).toBe(3)

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
    await createPage(page, 'Media drop refused', '10 MEDIA DROP TEST', 'Image Row')
    const row = rows(page).first()

    await drop(page, row.locator('.block-media-drop'), [
      ['test.pdf', 'application/pdf'],
      ['image.jpg', 'image/jpeg'],
    ])

    await expect(page.getByRole('dialog').filter({ hasText: 'test.pdf' })).toBeVisible()
    await expect(entries(row)).toHaveCount(1)
    await expect(field(entries(row).first())).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  })

  test('an entry whose upload is cancelled goes again', async ({ page }) => {
    await createPage(page, 'Media drop cancelled', '10 MEDIA DROP TEST', 'Image Row')
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

  test('a multi block without media_drop shows no drop zone', async ({ page }) => {
    await createPage(page, 'Media drop none', '06 COPY PASTE TEST', 'Team Section')
    await expect(rows(page)).toHaveCount(1)
    await expect(page.locator('.block-media-drop')).toHaveCount(0)
  })
})
