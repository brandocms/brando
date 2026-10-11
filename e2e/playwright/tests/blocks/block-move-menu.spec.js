import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// "Flytt opp" and "Flytt ned" in a block's menu: moving blocks without
// dragging. They go through the same reposition a drag sends, so the order
// is the block field's and is saved with the entry. Driven in Norwegian.

test.describe('Moving blocks from their menu', () => {
  test.setTimeout(90000)

  const rootBlocks = page => page.locator('.entry-block')
  const headers = page => page.locator('.entry-block .header-block textarea')

  const addStyledHeader = async (page, text) => {
    const index = await rootBlocks(page).count()
    await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Stilisert overskrift' }).click()
    await syncLV(page)
    const textarea = headers(page).nth(index)
    await textarea.fill(text)
    await textarea.blur()
    await syncLV(page)
  }

  // The block's own menu, not one of a block inside it
  const menu = (page, index) => rootBlocks(page).nth(index).locator('.block-action-dropdown').first()

  const openMenu = async (page, index) => {
    await menu(page, index).getByRole('button', { name: 'Handlinger', exact: true }).click()
    return menu(page, index).locator('.block-action-dropdown-content')
  }

  const move = async (page, index, name) => {
    await awaitBlockShip(page)
    const items = await openMenu(page, index)
    await items.getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }

  const expectOrder = async (page, texts) => {
    await expect(headers(page)).toHaveCount(texts.length)
    for (let i = 0; i < texts.length; i++) await expect(headers(page).nth(i)).toHaveValue(texts[i])
  }

  test('moves a block up and down, and the order is saved', async ({ page }) => {
    expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.setViewportSize({ width: 1440, height: 2600 })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('input[name="page[title]"]').fill('Flytt blokker')
    await page.locator('input[name="page[uri]"]').fill('flytt-blokker')

    await addStyledHeader(page, 'Alfa')
    await addStyledHeader(page, 'Beta')
    await addStyledHeader(page, 'Gamma')
    await expectOrder(page, ['Alfa', 'Beta', 'Gamma'])

    // Nothing above the first block, nothing below the last
    let items = await openMenu(page, 0)
    await expect(items.getByRole('button', { name: 'Flytt opp', exact: true })).toBeDisabled()
    await expect(items.getByRole('button', { name: 'Flytt ned', exact: true })).toBeEnabled()
    // A click on another block's menu closes this one
    items = await openMenu(page, 2)
    await expect(items.getByRole('button', { name: 'Flytt ned', exact: true })).toBeDisabled()
    await expect(items.getByRole('button', { name: 'Flytt opp', exact: true })).toBeEnabled()
    await openMenu(page, 2)

    await move(page, 2, 'Flytt opp')
    await expectOrder(page, ['Alfa', 'Gamma', 'Beta'])
    await move(page, 0, 'Flytt ned')
    await expectOrder(page, ['Gamma', 'Alfa', 'Beta'])

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await page.getByRole('link', { name: 'Flytt blokker', exact: true }).click()
    await syncLV(page)
    await expectOrder(page, ['Gamma', 'Alfa', 'Beta'])
  })
})
