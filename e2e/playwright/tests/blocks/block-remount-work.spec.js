import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// An entry moved to another row mounts again under its new parent. What the
// editor had typed into it a moment before, still inside the field's
// debounce, goes with it: moved by this editor, or by another.
test.describe('Block editor: work in a block that mounts again', () => {
  test.setTimeout(120000)
  // Sortable's fallback drag finds its target with elementFromPoint: the
  // handle and the target row have to be on screen together.
  test.use({ viewport: { width: 1280, height: 2600 } })

  const rows = page => page.locator('[data-module-multi="true"]')
  const entries = row => row.locator('.block-children > [data-uid]')
  const nameField = entry => entry.locator('.block-vars').getByLabel('Name')
  const names = async row => {
    const values = []
    for (const entry of await entries(row).all()) values.push(await nameField(entry).inputValue())
    return values
  }

  const addRow = async (page, group, module) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: group }).click()
    await page.getByRole('button', { name: module }).click()
    await syncLV(page)
  }

  const addEntry = async (page, row, name) => {
    const count = await entries(row).count()
    await row.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)
    await expect(entries(row)).toHaveCount(count + 1)
    const input = nameField(entries(row).nth(count))
    await input.fill(name)
    await input.blur()
    await syncLV(page)
  }

  // A Team Section with Alice and Bob, and one with Carol
  const createPage = async (page, title) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    await addEntry(page, rows(page).nth(0), 'Alice')
    await addEntry(page, rows(page).nth(0), 'Bob')
    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    await addEntry(page, rows(page).nth(1), 'Carol')
    await awaitBlockShip(page)
  }

  const saveAndContinue = async page => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(entries(rows(page).nth(1))).toHaveCount(1, { timeout: 15000 })
  }

  // `entry` picked up by its handle and held below the last entry of `row`
  const pickUpAndHold = async (page, entry, row) => {
    const handle = await entry.locator('.sort-handle').first().boundingBox()
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2)
    await page.mouse.down()
    await page.mouse.move(handle.x + handle.width / 2, handle.y + handle.height / 2 + 10, { steps: 2 })
    const last = await entries(row).last().boundingBox()
    await page.mouse.move(last.x + last.width / 2, last.y + last.height - 8, { steps: 20 })
  }

  const reopen = async (page, title) => {
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: title, exact: true }).click()
    await syncLV(page)
  }

  test('text typed just before the editor drags the entry to another row goes with it', async ({ page }) => {
    const title = 'Remount typed own move'
    await createPage(page, title)
    const [first, second] = [rows(page).nth(0), rows(page).nth(1)]

    await nameField(entries(first).nth(1)).fill('Bobby')
    await pickUpAndHold(page, entries(first).nth(1), second)
    await page.mouse.up()
    await syncLV(page)

    await expect.poll(() => names(first)).toEqual(['Alice'])
    await expect.poll(() => names(second)).toEqual(['Carol', 'Bobby'])

    await awaitBlockShip(page)
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await reopen(page, title)
    await expect.poll(() => names(rows(page).nth(1))).toEqual(['Carol', 'Bobby'])
  })

  test('text typed in an entry another editor moves to another row goes with it', async ({ page, secondUserPage }) => {
    const title = 'Remount typed other move'
    await createPage(page, title)
    await saveAndContinue(page)

    const other = secondUserPage
    await other.goto(page.url())
    await syncLV(other)
    await expect.poll(() => names(rows(other).nth(0))).toEqual(['Alice', 'Bob'])

    // The other editor holds Bob over Carol's row, this editor types in
    // Bob's name, and the other lets go inside the field's debounce
    const bob = nameField(entries(rows(page).nth(0)).nth(1))
    await bob.click()
    await pickUpAndHold(other, entries(rows(other).nth(0)).nth(1), rows(other).nth(1))
    await bob.fill('Bobby')
    await other.mouse.up()
    await syncLV(other)

    await expect.poll(() => names(rows(page).nth(1))).toEqual(['Carol', 'Bobby'])
    // and this editor is still in the field
    await expect(nameField(entries(rows(page).nth(1)).nth(1))).toBeFocused()
    await expect.poll(() => names(rows(page).nth(0))).toEqual(['Alice'])
    await expect.poll(() => names(rows(other).nth(1))).toEqual(['Carol', 'Bobby'])

    await awaitBlockShip(page)
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await reopen(page, title)
    await expect.poll(() => names(rows(page).nth(1))).toEqual(['Carol', 'Bobby'])
  })
})
