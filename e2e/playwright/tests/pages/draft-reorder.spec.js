import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip, confirmUploadFolder } from '../../utils'

async function addBlock(page, name) {
  await page.getByRole('button', { name: 'Add block' }).last().click()
  await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
  await page.getByRole('button', { name, exact: true }).click()
  await syncLV(page)
}

// Moves `items.nth(from)` to the front of its list. Sortable only reorders once
// the pointer has crossed the target's swap threshold, so releasing as soon as
// the mouse arrives can drop the item back where it started. Hold the button
// until the drop indicator (`is-sorting`, the ghost class) sits at the front.
async function dragToFront(page, items, from, handleSelector) {
  await syncLV(page)
  const handle = handleSelector ? items.nth(from).locator(handleSelector).first() : items.nth(from)
  const target = items.first()
  await handle.scrollIntoViewIfNeeded()
  await target.scrollIntoViewIfNeeded()
  const source = await handle.boundingBox()
  const destination = await target.boundingBox()
  await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2)
  await page.mouse.down()
  await page.mouse.move(source.x + source.width / 2 + 12, source.y + source.height / 2, { steps: 4 })
  await expect(page.locator('.sortable-fallback')).toBeVisible()
  await page.mouse.move(destination.x + 8, destination.y + 8, { steps: 25 })
  await expect
    .poll(() => items.evaluateAll(els => els.findIndex(el => el.classList.contains('is-sorting'))))
    .toBe(0)
  await page.mouse.up()
  await syncLV(page)
}

test('recovery shows block and gallery moves, preserves accompanying edits and lets wheel scroll the page', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  await page.setViewportSize({ width: 1440, height: 2400 })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Recovery order review')
  await page.getByLabel('URI', { exact: true }).fill('recovery-order-review')
  const headers = page.locator('.header-block textarea')
  // The picker hands the insert to the block field with a `send_update`, which
  // renders after the click has been answered, so `syncLV` can return before
  // the new block exists and `last()` still resolves to the previous header.
  // Wait for the new block, still carrying the module's default text, before
  // typing into it.
  for (const text of ['Opening story', 'Closing story']) {
    const count = await headers.count()
    await addBlock(page, 'Styled Header')
    await expect(headers).toHaveCount(count + 1)
    await expect(headers.last()).toHaveValue('Header Text')
    await headers.last().fill(text)
    await headers.last().blur()
    await awaitBlockShip(page)
  }
  await addBlock(page, 'Gallery with Controls')
  const gallery = page.locator('.gallery-block')
  await gallery.locator('.file-input').setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
  await confirmUploadFolder(page)
  await expect(gallery.locator('.gallery-object')).toHaveCount(2, { timeout: 30000 })
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
  await page.getByRole('link', { name: 'Recovery order review', exact: true }).click()
  await syncLV(page)
  const id = new URL(page.url()).pathname.split('/').at(-1)
  await expect(headers.nth(0)).toHaveValue('Opening story')
  await expect(headers.nth(1)).toHaveValue('Closing story')
  await dragToFront(page, page.locator('.entry-block'), 1, '.sort-handle')
  await expect(headers.first()).toHaveValue('Closing story')
  const objects = gallery.locator('.gallery-object')
  const beforeIds = await objects.evaluateAll(nodes => nodes.map(node => node.id))
  await dragToFront(page, objects, beforeIds.length - 1)
  await expect.poll(() => objects.evaluateAll(nodes => nodes.map(node => node.id))).toEqual([...beforeIds].reverse())
  await headers.first().fill('Closing story, revised')
  await headers.first().blur()
  await expect.poll(async () => {
    const response = await page.request.post('/e2e/drafts/media-state', { data: { schema: 'page', entry_id: id } })
    const state = await response.json()
    return state.drafts.some(copy => JSON.stringify(copy).includes('Closing story, revised'))
  }, { timeout: 25000 }).toBe(true)
  await page.reload()
  await page.getByRole('button', { name: 'Review recovery copy', exact: true }).click()
  const preview = page.locator('.draft-content-preview')
  const orders = preview.locator('.draft-order-diff')
  await expect(orders).toHaveCount(2)
  await expect(orders.first()).toContainText('Block order')
  await expect(orders.first()).toContainText('Closing story, revised')
  await expect(orders.last()).toContainText('Gallery order')
  await expect(orders.last().locator('img')).toHaveCount(2)
  await expect(preview.locator('.text-diff-line.is-del:visible')).toHaveCount(1)
  await expect(preview.locator('.text-diff-line.is-ins:visible')).toHaveCount(1)
  await expect(preview.locator('ins:visible')).toContainText('Closing story, revised')
  await expect(preview.locator('del:visible')).toContainText('Closing story')
  await expect(preview.locator('.draft-preview-unchanged')).toHaveCount(0)
  await page.setViewportSize({ width: 1440, height: 1000 })
  await preview.evaluate(el => el.scrollIntoView({ block: 'start' }))
  await expect.poll(() => orders.locator('img').evaluateAll(images => images.every(img => img.complete && img.naturalWidth > 0))).toBe(true)
  await preview.screenshot({ path: testInfo.outputPath('recovery-order-desktop.png') })

  const line = preview.locator('.text-diff-line.is-ins:visible').first()
  await line.hover()
  const top = await page.evaluate(() => window.scrollY)
  await page.mouse.wheel(0, 450)
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeGreaterThan(top + 100)
  const bottom = await page.evaluate(() => window.scrollY)
  await page.mouse.wheel(0, -350)
  await expect.poll(() => page.evaluate(() => window.scrollY)).toBeLessThan(bottom - 100)

  await preview.getByRole('checkbox', { name: 'Show unchanged content' }).check()
  await expect(preview.locator('.text-diff-line.is-eq:visible').first()).toBeVisible()
  await preview.getByRole('checkbox', { name: 'Show unchanged content' }).uncheck()
  await page.setViewportSize({ width: 390, height: 1000 })
  await preview.evaluate(el => el.scrollIntoView({ block: 'start' }))
  await expect.poll(() => preview.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
  await preview.screenshot({ path: testInfo.outputPath('recovery-order-mobile.png') })

  await page.setViewportSize({ width: 1440, height: 2400 })
  await page.getByRole('button', { name: 'Restore recovery copy', exact: true }).click()
  await expect(page.getByTestId('draft-panel')).toHaveCount(0)
  await expect(headers.first()).toHaveValue('Closing story, revised')
  await expect.poll(() => objects.evaluateAll(nodes => nodes.map(node => node.id))).toEqual([...beforeIds].reverse())
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
  await page.getByRole('link', { name: 'Recovery order review', exact: true }).click()
  await syncLV(page)
  await expect(headers.first()).toHaveValue('Closing story, revised')
  await expect.poll(() => objects.evaluateAll(nodes => nodes.map(node => node.id))).toEqual([...beforeIds].reverse())
  await expect(page.getByTestId('draft-notice')).toHaveCount(0)
})
