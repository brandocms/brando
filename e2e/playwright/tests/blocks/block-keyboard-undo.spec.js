import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// ⌘Z (Ctrl+Z) outside a text field undoes the last block moved or deleted,
// newest first: a delete comes back as with the notice's "Angre", a move goes
// back where it was. In a text field ⌘Z stays the field's own undo of typing.
// Driven in Norwegian.

test.describe('Undoing block changes with the keyboard', () => {
  test.setTimeout(120000)

  const rootBlocks = page => page.locator('.entry-block')
  const headers = page => page.locator('.entry-block .header-block textarea')

  const addStyledHeader = async (page, text) => {
    const index = await rootBlocks(page).count()
    await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Stilisert overskrift', exact: true }).click()
    await syncLV(page)
    const textarea = headers(page).nth(index)
    await textarea.fill(text)
    await textarea.blur()
    await syncLV(page)
  }

  const menu = (page, index) => rootBlocks(page).nth(index).locator('.block-action-dropdown').first()

  const choose = async (page, index, name) => {
    await awaitBlockShip(page)
    await menu(page, index).getByRole('button', { name: 'Handlinger', exact: true }).click()
    await menu(page, index).locator('.block-action-dropdown-content').getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }

  const expectOrder = async (page, texts) => {
    await expect(headers(page)).toHaveCount(texts.length)
    for (let i = 0; i < texts.length; i++) await expect(headers(page).nth(i)).toHaveValue(texts[i])
  }

  const undoOutsideFields = async page => {
    await page.evaluate(() => document.activeElement?.blur())
    await page.keyboard.press('ControlOrMeta+z')
    await syncLV(page)
  }

  test('undoes a delete, then a move, and leaves typing to the field', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.setViewportSize({ width: 1440, height: 2600 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill('Angre blokker')
    await page.locator('input[name="page[uri]"]').fill('angre-blokker')

    await addStyledHeader(page, 'Alfa')
    await addStyledHeader(page, 'Beta')
    await addStyledHeader(page, 'Gamma')

    await choose(page, 2, 'Flytt opp')
    await expectOrder(page, ['Alfa', 'Gamma', 'Beta'])
    await choose(page, 0, 'Slett')
    await expectOrder(page, ['Gamma', 'Beta'])
    await expect(page.getByTestId('block-bin')).toBeVisible()

    // In a text field ⌘Z undoes the typing, and no block comes back
    const beta = headers(page).nth(1)
    await beta.click()
    await beta.press('End')
    await page.keyboard.type(' to')
    await expect(beta).toHaveValue('Beta to')
    await page.keyboard.press('ControlOrMeta+z')
    await expect(beta).toHaveValue('Beta')
    await syncLV(page)
    await expect(headers(page)).toHaveCount(2)

    // Outside it: the delete first, back where it was, and the notice goes
    await undoOutsideFields(page)
    await expectOrder(page, ['Alfa', 'Gamma', 'Beta'])
    await expect(page.getByTestId('block-bin')).not.toBeVisible()

    // then the move
    await undoOutsideFields(page)
    await expectOrder(page, ['Alfa', 'Beta', 'Gamma'])

    // Nothing left to undo
    await undoOutsideFields(page)
    await expectOrder(page, ['Alfa', 'Beta', 'Gamma'])

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await page.getByRole('link', { name: 'Angre blokker', exact: true }).click()
    await syncLV(page)
    await expectOrder(page, ['Alfa', 'Beta', 'Gamma'])
  })

  test('a change it cannot undo ends what ⌘Z undoes', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.setViewportSize({ width: 1440, height: 2600 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill('Angre etter innsetting')
    await page.locator('input[name="page[uri]"]').fill('angre-etter-innsetting')

    await addStyledHeader(page, 'Alfa')
    await addStyledHeader(page, 'Beta')
    await choose(page, 0, 'Slett')
    await expectOrder(page, ['Beta'])

    // An insert is not on the stack: ⌘Z neither takes it out nor brings the
    // deleted block back past it. The notice still can.
    await addStyledHeader(page, 'Delta')
    await undoOutsideFields(page)
    await expectOrder(page, ['Beta', 'Delta'])
    await expect(page.getByTestId('block-bin')).toBeVisible()
  })

  test("another editor's move ends what ⌘Z undoes", async ({ page, secondUserPage }) => {
    await page.setViewportSize({ width: 1440, height: 2600 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill('Undo after a remote move')
    await page.locator('input[name="page[uri]"]').fill('undo-after-a-remote-move')

    const addEnglishHeader = async (text) => {
      const index = await rootBlocks(page).count()
      await page.getByRole('button', { name: 'Add block' }).last().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
      await page.getByRole('button', { name: 'Styled Header', exact: true }).click()
      await syncLV(page)
      const textarea = headers(page).nth(index)
      await textarea.fill(text)
      await textarea.blur()
      await syncLV(page)
    }

    for (const text of ['Alfa', 'Beta', 'Gamma']) await addEnglishHeader(text)

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expectOrder(page, ['Alfa', 'Beta', 'Gamma'])

    await secondUserPage.setViewportSize({ width: 1440, height: 2600 })
    await secondUserPage.goto(new URL(page.url()).pathname)
    await syncLV(secondUserPage)
    await expectOrder(secondUserPage, ['Alfa', 'Beta', 'Gamma'])

    const moveAs = async (who, index, name) => {
      await awaitBlockShip(who)
      const blockMenu = rootBlocks(who).nth(index).locator('.block-action-dropdown').first()
      await blockMenu.getByRole('button', { name: 'More actions', exact: true }).click()
      await blockMenu.locator('.block-action-dropdown-content').getByRole('button', { name, exact: true }).click()
      await syncLV(who)
    }

    // A moves Gamma up; then B moves Alfa down, which A sees
    await moveAs(page, 2, 'Move up')
    await expectOrder(page, ['Alfa', 'Gamma', 'Beta'])
    await expectOrder(secondUserPage, ['Alfa', 'Gamma', 'Beta'])
    await moveAs(secondUserPage, 0, 'Move down')
    await expectOrder(page, ['Gamma', 'Alfa', 'Beta'])

    // A's ⌘Z does not put Gamma back by its old index among B's order
    await undoOutsideFields(page)
    await expectOrder(page, ['Gamma', 'Alfa', 'Beta'])
  })

  test('undoes a reorder of a block’s children', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.setViewportSize({ width: 1440, height: 2600 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill('Angre barn')
    await page.locator('input[name="page[uri]"]').fill('angre-barn')

    await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Teamblokk', exact: true }).click()
    await syncLV(page)

    const multiBlock = page.locator('[data-module-multi="true"]')
    const members = multiBlock.locator('.block-children [data-uid]')

    for (const name of ['Ada', 'Bo']) {
      await multiBlock.locator('.block-plus').last().click()
      await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
      await page.getByRole('button', { name: /^Teammedlem\b/ }).click()
      await syncLV(page)
      const nameInput = members.last().locator('.block-vars').getByLabel('Name')
      await nameInput.fill(name)
      await nameInput.blur()
      await syncLV(page)
    }

    const names = () => members.locator('.block-vars').getByLabel('Name')
    await expect(names()).toHaveCount(2)
    await expect(names().nth(0)).toHaveValue('Ada')

    await awaitBlockShip(page)
    const memberMenu = members.first().locator('.block-action-dropdown').first()
    await memberMenu.getByRole('button', { name: 'Handlinger', exact: true }).click()
    await memberMenu.locator('.block-action-dropdown-content').getByRole('button', { name: 'Flytt ned', exact: true }).click()
    await syncLV(page)
    await expect(names().nth(0)).toHaveValue('Bo')
    await expect(names().nth(1)).toHaveValue('Ada')

    await undoOutsideFields(page)
    await expect(names().nth(0)).toHaveValue('Ada')
    await expect(names().nth(1)).toHaveValue('Bo')
  })
})
