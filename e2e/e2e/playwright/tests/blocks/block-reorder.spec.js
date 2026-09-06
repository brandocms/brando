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

    await page.getByRole('link', { name: 'Reorder Test →' }).click()
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

    await page.getByRole('link', { name: 'Reorder Roundtrip Test →' }).click()
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

    await page.getByRole('link', { name: 'Multi Entry Reorder Test →' }).click()
    await syncLV(page)
    await expectMemberOrder(['Charlie', 'Alice', 'Bob'])
  })
})
