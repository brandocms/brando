import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// A block moved, by a drag or by Move up / Move down, shows a "Block moved"
// notice whose Undo puts it back. ⌘Z (Ctrl+Z) outside a text field undoes the
// move as well, and ⌘⇧Z makes it again; in a text field both keys stay the
// field's own undo and redo of typing. Driven in Norwegian.

test.describe('Undoing and redoing block moves', () => {
  test.setTimeout(120000)

  // SortableJS's fallback drag finds drop targets with elementFromPoint, so the
  // handle and the target must both be on screen: a tall viewport keeps the
  // three blocks there without autoscroll mid-drag.
  test.use({ viewport: { width: 1440, height: 2600 } })

  const rootBlocks = page => page.locator('.entry-block')
  const headers = page => page.locator('.entry-block .header-block textarea')

  const createPage = async (page, title, uri) => {
    expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill(title)
    await page.locator('input[name="page[uri]"]').fill(uri)
  }

  const addStyledHeader = async (page, text) => {
    const index = await rootBlocks(page).count()
    await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Stilisert overskrift', exact: true }).click()
    await syncLV(page)
    const textarea = headers(page).nth(index)
    await textarea.fill(text)
    // Blur to flush the debounced validate now: a focusout firing mid-drag
    // re-renders the block under SortableJS's dragged element.
    await textarea.blur()
    await syncLV(page)
  }

  const expectOrder = async (page, texts) => {
    await expect(headers(page)).toHaveCount(texts.length)
    for (let i = 0; i < texts.length; i++) await expect(headers(page).nth(i)).toHaveValue(texts[i])
  }

  // Drag `from` by its handle to `to`, releasing once Sortable's ghost
  // (`is-sorting`) sits there (see block-reorder.spec.js for why).
  const dragBlock = async (page, from, to) => {
    await awaitBlockShip(page)
    const items = rootBlocks(page)
    const sourceHandle = items.nth(from).locator('.sort-handle').first()
    const target = items.nth(to)
    await sourceHandle.scrollIntoViewIfNeeded()
    await target.scrollIntoViewIfNeeded()
    const sourceBox = await sourceHandle.boundingBox()
    const targetBox = await target.boundingBox()
    const targetY = to < from ? targetBox.y + 8 : targetBox.y + targetBox.height - 8

    await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2)
    await page.mouse.down()
    await page.waitForTimeout(100)
    await page.mouse.move(targetBox.x + targetBox.width / 2, targetY, { steps: 20 })
    await expect
      .poll(() => items.evaluateAll(els => els.findIndex(el => el.classList.contains('is-sorting'))))
      .toBe(to)
    await page.mouse.up()
    await syncLV(page)
  }

  const choose = async (page, index, name) => {
    await awaitBlockShip(page)
    const menu = rootBlocks(page).nth(index).locator('.block-action-dropdown').first()
    await menu.getByRole('button', { name: 'Handlinger', exact: true }).click()
    await menu.locator('.block-action-dropdown-content').getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }

  const outsideFields = async (page, keys) => {
    await page.evaluate(() => document.activeElement?.blur())
    await page.keyboard.press(keys)
    await syncLV(page)
  }

  const notice = page => page.getByTestId('block-moved')

  test('a drag is undone and redone with the keyboard, outside a text field only', async ({ page }) => {
    await createPage(page, 'Angre flytting', 'angre-flytting')
    for (const text of ['Alfa', 'Beta', 'Gamma']) await addStyledHeader(page, text)

    await dragBlock(page, 0, 2)
    await expectOrder(page, ['Beta', 'Gamma', 'Alfa'])
    await expect(notice(page)).toBeVisible()

    // In a text field the keys undo and redo the typing, and no block moves
    const beta = headers(page).nth(0)
    await beta.click()
    await beta.press('End')
    await page.keyboard.type(' to')
    await expect(beta).toHaveValue('Beta to')
    await page.keyboard.press('ControlOrMeta+z')
    await expect(beta).toHaveValue('Beta')
    await page.keyboard.press('ControlOrMeta+Shift+z')
    await expect(beta).toHaveValue('Beta to')
    await syncLV(page)
    await expectOrder(page, ['Beta to', 'Gamma', 'Alfa'])

    // Outside it: the move goes back, and its notice with it
    await outsideFields(page, 'ControlOrMeta+z')
    await expectOrder(page, ['Alfa', 'Beta to', 'Gamma'])
    await expect(notice(page)).toBeHidden()

    // and comes again
    await outsideFields(page, 'ControlOrMeta+Shift+z')
    await expectOrder(page, ['Beta to', 'Gamma', 'Alfa'])
    await expect(notice(page)).toBeVisible()

    // Nothing left to redo
    await outsideFields(page, 'ControlOrMeta+Shift+z')
    await expectOrder(page, ['Beta to', 'Gamma', 'Alfa'])

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await page.getByRole('link', { name: 'Angre flytting', exact: true }).click()
    await syncLV(page)
    await expectOrder(page, ['Beta to', 'Gamma', 'Alfa'])
  })

  test("Move down is undone from the notice's Undo", async ({ page }) => {
    await createPage(page, 'Angre flytt ned', 'angre-flytt-ned')
    for (const text of ['Alfa', 'Beta']) await addStyledHeader(page, text)

    await choose(page, 0, 'Flytt ned')
    await expectOrder(page, ['Beta', 'Alfa'])

    await notice(page).getByRole('button', { name: 'Angre', exact: true }).click()
    await syncLV(page)
    await expectOrder(page, ['Alfa', 'Beta'])
    await expect(notice(page)).toBeHidden()

    // ⌘⇧Z moves it down again
    await outsideFields(page, 'ControlOrMeta+Shift+z')
    await expectOrder(page, ['Beta', 'Alfa'])

    // Dismissed, the notice goes, and ⌘Z still undoes the move
    await notice(page).getByRole('button', { name: 'Fjern', exact: true }).click()
    await syncLV(page)
    await expect(notice(page)).toBeHidden()
    await outsideFields(page, 'ControlOrMeta+z')
    await expectOrder(page, ['Alfa', 'Beta'])
  })
})
