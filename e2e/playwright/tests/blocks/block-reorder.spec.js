import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate,
} from '../../utils'

// Regression coverage for root-block drag reordering — the `reposition` event
// pushed by the Brando.SortableBlocks hook. This path had no e2e coverage
// before Phase 3 of the block-editor refactor keyed the root block list on uid
// (`:for`/`:key` in block_field.ex). These specs pin down reorder behaviour
// (editor order, preview refresh after the position-ack handshake, and
// persistence) before the reorder flow is rewritten as a single {:move, ...} op.
test.describe('Block reordering (root blocks)', () => {
  test.setTimeout(60000)

  // SortableJS fallback dragging resolves drop targets with elementFromPoint,
  // so the drag handle AND the drop target must be inside the viewport at the
  // same time. Three Styled Header blocks span ~2100px — a default 720px-tall
  // viewport triggers mid-drag autoscroll, which invalidates the coordinates
  // captured before the drag. A tall viewport keeps every block on screen.
  test.use({ viewport: { width: 1280, height: 2600 } })

  const createPage = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)
  }

  const addStyledHeader = async (page, text, textIndex) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)
    const textarea = page.locator('.header-block textarea').nth(textIndex)
    await textarea.fill(text)
    // Blur to flush the debounced validate now — a focusout firing mid-drag
    // triggers an LV re-render that detaches SortableJS's dragged element.
    await textarea.blur()
    await syncLV(page)
  }

  // SortableJS needs incremental mouse movement for its drag-over detection —
  // a single-jump mouse.move never triggers the reorder. `edge` picks whether
  // we aim just inside the target's top or bottom edge, which decides whether
  // Sortable drops the dragged block before or after the target.
  const dragBlock = async (page, sourceHandle, target, edge) => {
    // syncLV only waits for pending client-initiated events; the position
    // handshake after an insert re-renders blocks server-side slightly later,
    // and a patch landing mid-drag detaches the dragged element. Let it settle.
    await page.waitForTimeout(750)
    await sourceHandle.scrollIntoViewIfNeeded()
    await target.scrollIntoViewIfNeeded()
    const sourceBox = await sourceHandle.boundingBox()
    const targetBox = await target.boundingBox()
    const targetY = edge === 'top' ? targetBox.y + 8 : targetBox.y + targetBox.height - 8

    await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2)
    await page.mouse.down()
    await page.waitForTimeout(100)
    await page.mouse.move(targetBox.x + targetBox.width / 2, targetY, { steps: 20 })
    await page.waitForTimeout(100)
    await page.mouse.up()
    await syncLV(page)
  }

  const sortHandle = (page, index) => page.locator('.entry-block').nth(index).locator('.sort-handle').first()

  const expectHeaderOrder = async (page, texts) => {
    for (let i = 0; i < texts.length; i++) {
      await expect(page.locator('.header-block textarea').nth(i)).toHaveValue(texts[i])
    }
  }

  test('drag-reordering root blocks updates editor + preview and persists after save', async ({ page }) => {
    await createPage(page, 'Reorder Test', 'reorder-test')

    await addStyledHeader(page, 'Alpha', 0)
    await addStyledHeader(page, 'Beta', 1)
    await addStyledHeader(page, 'Gamma', 2)
    await expectHeaderOrder(page, ['Alpha', 'Beta', 'Gamma'])

    await toggleLivePreview(page)
    await waitForPreviewReady(page)
    const frame = getPreviewFrame(page)
    const previewHeaders = frame.locator('header[b-tpl="styled-header"] h1')
    await expect(previewHeaders.nth(0)).toContainText('Alpha')

    // Drag Gamma (3rd block) to the top → [Gamma, Alpha, Beta]
    await dragBlock(page, sortHandle(page, 2), page.locator('.entry-block').nth(0), 'top')
    await expectHeaderOrder(page, ['Gamma', 'Alpha', 'Beta'])

    // The preview refresh is gated on every root block acking its new
    // sequence — the reordered result must still reach the preview.
    await waitForPreviewUpdate(page)
    await expect(previewHeaders.nth(0)).toContainText('Gamma')
    await expect(previewHeaders.nth(1)).toContainText('Alpha')
    await expect(previewHeaders.nth(2)).toContainText('Beta')

    // Save, reopen, verify the order actually persisted.
    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: 'Reorder Test', exact: true }).click()
    await syncLV(page)
    await expectHeaderOrder(page, ['Gamma', 'Alpha', 'Beta'])
  })

  test('reordering up then back down restores the original order', async ({ page }) => {
    await createPage(page, 'Reorder Roundtrip Test', 'reorder-roundtrip-test')

    await addStyledHeader(page, 'Alpha', 0)
    await addStyledHeader(page, 'Beta', 1)
    await addStyledHeader(page, 'Gamma', 2)

    // Gamma to the top → [Gamma, Alpha, Beta]
    await dragBlock(page, sortHandle(page, 2), page.locator('.entry-block').nth(0), 'top')
    await expectHeaderOrder(page, ['Gamma', 'Alpha', 'Beta'])

    // Gamma (now 1st) back to the bottom → [Alpha, Beta, Gamma]
    await dragBlock(page, sortHandle(page, 0), page.locator('.entry-block').nth(2), 'bottom')
    await expectHeaderOrder(page, ['Alpha', 'Beta', 'Gamma'])

    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: 'Reorder Roundtrip Test', exact: true }).click()
    await syncLV(page)
    await expectHeaderOrder(page, ['Alpha', 'Beta', 'Gamma'])
  })

  test('drag-reordering multi-block entries persists after save', async ({ page }) => {
    await page.goto('/admin/pages')
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Multi Entry Reorder Test')
    await page.getByLabel('URI').fill('multi-entry-reorder-test')

    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]')
    const childEntries = multiBlock.locator('.block-children > [data-uid]')

    for (const [index, name] of ['Alice', 'Bob', 'Charlie'].entries()) {
      await multiBlock.locator('.block-plus').last().click()
      await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
      await page.getByRole('button', { name: /^Team Member\b/ }).click()
      await syncLV(page)
      await expect(childEntries).toHaveCount(index + 1)

      const nameInput = childEntries.nth(index).locator('.block-vars').getByLabel('Name')
      await nameInput.fill(name)
      await nameInput.blur()
      await syncLV(page)
    }

    const expectMemberOrder = async (names) => {
      for (let index = 0; index < names.length; index++) {
        await expect(childEntries.nth(index).locator('.block-vars').getByLabel('Name')).toHaveValue(
          names[index]
        )
      }
    }

    await expectMemberOrder(['Alice', 'Bob', 'Charlie'])
    await dragBlock(
      page,
      childEntries.nth(2).locator('.sort-handle').first(),
      childEntries.nth(0),
      'top'
    )
    await expectMemberOrder(['Charlie', 'Alice', 'Bob'])

    await page.getByRole('button', { name: 'Save', exact: true }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)

    await page.getByRole('link', { name: 'Multi Entry Reorder Test', exact: true }).click()
    await syncLV(page)
    await expectMemberOrder(['Charlie', 'Alice', 'Bob'])
  })

  // The two halves of a drag have to be told apart on sight, and the one under
  // the cursor has to stay under the cursor. Both were broken: the drop
  // indicator rendered as an ordinary block at 50% opacity (two plausible
  // copies, neither obviously "the one I'm holding"), and the cursor-following
  // clone drifted away from the pointer whenever anything under the drag
  // scrolled or re-rendered — the drop landed correctly, but the block appeared
  // to jump several positions.
  test.describe('drag affordances', () => {
    const startDrag = async (page, handle) => {
      await page.waitForTimeout(750)
      await handle.scrollIntoViewIfNeeded()
      const box = await handle.boundingBox()
      const start = { x: box.x + box.width / 2, y: box.y + box.height / 2 }
      await page.mouse.move(start.x, start.y)
      await page.mouse.down()
      // Past `fallbackTolerance`, so the drag is actually running.
      await page.mouse.move(start.x, start.y + 30, { steps: 10 })
      await page.waitForTimeout(100)
      return start
    }

    test('the cursor-following clone stays under the cursor as the drag moves', async ({ page }) => {
      await createPage(page, 'Drag Tracking Test', 'drag-tracking-test')
      await addStyledHeader(page, 'Alpha', 0)
      await addStyledHeader(page, 'Beta', 1)
      await addStyledHeader(page, 'Gamma', 2)

      const start = await startDrag(page, sortHandle(page, 2))
      const clone = page.locator('.sortable-fallback')
      await expect(clone).toBeVisible()

      // `fallbackOnBody` is the mechanism: anchored to <body>, the clone is
      // positioned in page coordinates, where no scroll container or transform
      // between it and the list can shift it out from under the pointer.
      await expect(
        clone.evaluate(el => el.parentElement.tagName)
      ).resolves.toBe('BODY')

      // Sortable only repositions the clone on a pointer move. Autoscroll can
      // change the scroll offset without one, which leaves the clone correct but
      // momentarily stale — indistinguishable from the bug if you measure right
      // then. So: let the scroll settle, nudge a pixel to let Sortable catch up,
      // and only then read the offset.
      const settleAndMeasure = async (cursor) => {
        await page.evaluate(
          () =>
            new Promise(resolve => {
              let last = window.scrollY
              let stable = 0
              const tick = () => {
                if (window.scrollY === last) stable++
                else {
                  stable = 0
                  last = window.scrollY
                }
                if (stable >= 3) resolve()
                else requestAnimationFrame(tick)
              }
              requestAnimationFrame(tick)
            })
        )
        await page.mouse.move(cursor.x + 1, cursor.y)
        await page.mouse.move(cursor.x, cursor.y)
        const box = await clone.boundingBox()
        return { x: cursor.x - box.x, y: cursor.y - box.y }
      }

      const startCursor = { x: start.x, y: start.y + 30 }
      const first = await settleAndMeasure(startCursor)

      // Move well up the list — the distance that used to open up the gap.
      const far = { x: start.x, y: start.y - 400 }
      await page.mouse.move(far.x, far.y, { steps: 20 })
      const second = await settleAndMeasure(far)

      // The grabbed point must sit at the same place inside the clone as it did
      // at drag start. A couple of px of rounding is fine; the bug was tens.
      expect(Math.abs(second.x - first.x)).toBeLessThan(4)
      expect(Math.abs(second.y - first.y)).toBeLessThan(4)

      await page.mouse.up()
      await syncLV(page)
    })

    test('the drop indicator renders as a dashed slot, not a second copy of the block', async ({
      page,
    }) => {
      await createPage(page, 'Drag Indicator Test', 'drag-indicator-test')
      await addStyledHeader(page, 'Alpha', 0)
      await addStyledHeader(page, 'Beta', 1)

      await startDrag(page, sortHandle(page, 1))

      // The sortable item is the uid wrapper (`.entry-block` at root) and the
      // block sits some way inside it, so this matches on the block rather than
      // on a fixed child step.
      const indicator = page.locator('.entry-block.is-sorting .base-block > .block').first()
      await expect(indicator).toBeAttached()

      const style = await indicator.evaluate(el => {
        const after = getComputedStyle(el, '::after')
        return {
          visibility: getComputedStyle(el).visibility,
          borderStyle: after.borderTopStyle,
          afterVisibility: after.visibility,
        }
      })

      // The block's own content is out of sight but still holds the slot open,
      // and the dashed outline is what marks the landing place.
      expect(style.visibility).toBe('hidden')
      expect(style.borderStyle).toBe('dashed')
      expect(style.afterVisibility).toBe('visible')

      await page.mouse.up()
      await syncLV(page)
    })

    // A drag is client-only state: SortableJS adds its classes after the server
    // rendered the element, so they are absent from the markup LiveView diffs
    // against, and a patch landing mid-drag restored the server's `class` and
    // took them with it. The drop indicator reverted to looking like an
    // ordinary block, mid-drag, and never recovered — while the clone kept its
    // own classes, being parked on <body> outside the LiveView tree.
    test('the drop indicator survives a LiveView patch landing mid-drag', async ({ page }) => {
      await createPage(page, 'Drag Patch Test', 'drag-patch-test')
      await addStyledHeader(page, 'Alpha', 0)
      await addStyledHeader(page, 'Beta', 1)
      await addStyledHeader(page, 'Gamma', 2)

      await startDrag(page, sortHandle(page, 2))

      const indicator = page.locator('.entry-block.is-sorting')
      await expect(indicator).toHaveCount(1)

      // Force a server round-trip that re-renders the form under the live drag.
      // Set the value and dispatch directly rather than typing: focusing the
      // field would end the drag before the patch could land on it.
      const triggered = await page.evaluate(() => {
        const input = [...document.querySelectorAll('input')].find(i => /\[title\]$/.test(i.name || ''))
        if (!input) return null
        input.value = 'Drag Patch Test Edited'
        input.dispatchEvent(new Event('input', { bubbles: true }))
        return input.name
      })
      expect(triggered).toBe('page[title]')
      await page.waitForTimeout(1200)

      await expect(indicator).toHaveCount(1)

      // And it keeps working as a drop indicator for the rest of the drag.
      await expect(page.locator('.entry-block.is-sorting .base-block > .block').first()).toBeAttached()

      await page.mouse.up()
      await syncLV(page)
    })
  })

  // Reordering a block used to rebuild every preview element after the change
  // point rather than move any of them: blocks are delimited by HTML comments,
  // which morphdom cannot match on, so it paired `main`'s children up by
  // position. A video block dragged to a new place came back as a fresh,
  // unbooted container — the preview re-initializing a video whose source never
  // changed (and the same for anything below an inserted or deleted block).
  //
  // Node identity is the property that matters, and it is what a mounted player
  // rides on, so that is what this asserts: tag the live node with an expando
  // (which no amount of attribute syncing can reinstate), reorder, and require
  // the same object to still be carrying the same content.
  test.describe('preview block identity', () => {
    test('reordering moves preview nodes instead of rebuilding them', async ({ page }) => {
      await createPage(page, 'Preview Identity Test', 'preview-identity-test')
      await addStyledHeader(page, 'Alpha', 0)
      await addStyledHeader(page, 'Beta', 1)
      await addStyledHeader(page, 'Gamma', 2)

      await toggleLivePreview(page)
      await waitForPreviewReady(page)
      const frame = getPreviewFrame(page)
      const headers = frame.locator('header[b-tpl="styled-header"]')
      await expect(headers.nth(0)).toContainText('Alpha')
      await expect(headers.nth(2)).toContainText('Gamma')

      // Expando, not an attribute: morphdom syncs attributes, so an attribute
      // would be stripped even when the node IS reused, and the test would fail
      // for the wrong reason.
      await headers.nth(2).evaluate(el => {
        el.__lpIdentityProbe = 'gamma'
      })

      // Gamma to the top → [Gamma, Alpha, Beta]
      await dragBlock(page, sortHandle(page, 2), page.locator('.entry-block').nth(0), 'top')
      await expectHeaderOrder(page, ['Gamma', 'Alpha', 'Beta'])
      await waitForPreviewUpdate(page)
      await expect(headers.nth(0)).toContainText('Gamma')

      // Same DOM object, now in first place — moved, not rebuilt.
      const probe = await headers.nth(0).evaluate(el => el.__lpIdentityProbe)
      expect(probe).toBe('gamma')

      // And the nodes it displaced are still the originals too.
      const rebuilt = await headers.nth(1).evaluate(el => el.__lpIdentityProbe)
      expect(rebuilt).toBeUndefined()
    })
  })
})
