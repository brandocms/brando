import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// An entry of a multi block dragged on the canvas into another block of the
// same multi module moves there. A multi block of another module does not
// take it: it is no drop target, and the entry stays where it was.
test.describe('Multi blocks: dragging an entry to another row', () => {
  test.setTimeout(90000)
  // Sortable's fallback drag finds its target with elementFromPoint: the
  // handle and the target row have to be on screen together.
  test.use({ viewport: { width: 1280, height: 2600 } })

  const rows = page => page.locator('[data-module-multi="true"]')
  const entries = row => row.locator('.block-children > [data-uid]')
  const names = async row => {
    const values = []
    for (const entry of await entries(row).all()) {
      values.push(await entry.locator('.block-vars').getByLabel('Name').inputValue())
    }
    return values
  }

  const addRow = async (page, group, module) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: group }).click()
    await page.getByRole('button', { name: module }).click()
    await syncLV(page)
  }

  const addEntry = async (page, row, group, module, name) => {
    const count = await entries(row).count()
    await row.locator('.block-plus').last().click()
    await page.getByRole('button', { name: group }).click()
    await page.getByRole('button', { name: module }).click()
    await syncLV(page)
    await expect(entries(row)).toHaveCount(count + 1)

    if (name) {
      const input = entries(row).nth(count).locator('.block-vars').getByLabel('Name')
      await input.fill(name)
      await input.blur()
      await syncLV(page)
    }
  }

  // A Team Section with Alice and Bob, a Fallback Group with a Fallback
  // Object, and a Team Section with Carol. A drag between the two Team
  // Sections crosses the Fallback Group, which does not take it.
  const createPage = async (page, title, uri) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    await addEntry(page, rows(page).nth(0), 'COPY PASTE TEST', /^Team Member\b/, 'Alice')
    await addEntry(page, rows(page).nth(0), 'COPY PASTE TEST', /^Team Member\b/, 'Bob')
    await addRow(page, 'REF FALLBACK TEST', 'Fallback Group')
    await addEntry(page, rows(page).nth(1), 'REF FALLBACK TEST', 'Fallback Object')
    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    await addEntry(page, rows(page).nth(2), 'COPY PASTE TEST', /^Team Member\b/, 'Carol')
  }

  // Picks up `entry` by its handle and holds it over the bottom edge of
  // `over`. The last edit's blur ships the block after a client-side timer,
  // and the patch that answers it must not land mid-drag.
  const pickUpAndHold = async (page, entry, over) => {
    await awaitBlockShip(page)
    const handle = entry.locator('.sort-handle').first()
    const handleBox = await handle.boundingBox()

    await page.mouse.move(handleBox.x + handleBox.width / 2, handleBox.y + handleBox.height / 2)
    await page.mouse.down()
    await page.waitForTimeout(100)
    // Past Sortable's tolerance: the drag starts, and an empty row that
    // takes the entry opens up for it
    await page.mouse.move(handleBox.x + handleBox.width / 2, handleBox.y + handleBox.height / 2 + 10, { steps: 2 })
    await holdOver(page, over)
  }

  const holdOver = async (page, over) => {
    const box = await over.boundingBox()
    await page.mouse.move(box.x + box.width / 2, box.y + Math.max(box.height / 2, box.height - 8), { steps: 20 })
  }

  const placeholderIndex = row =>
    entries(row).evaluateAll(els => els.findIndex(el => el.classList.contains('is-sorting')))

  test('an entry dragged into another row of its module moves there and is saved there', async ({ page }) => {
    await createPage(page, 'Multi Row Move', 'multi-row-move')
    const [first, other, second] = [rows(page).nth(0), rows(page).nth(1), rows(page).nth(2)]

    await pickUpAndHold(page, entries(first).nth(1), entries(second).nth(0))
    // The rows that take it say so while it is in hand; another module's
    // row does not.
    await expect(second.locator('.block-children')).toHaveClass(/is-drop-target/)
    await expect(other.locator('.block-children')).not.toHaveClass(/is-drop-target/)
    await expect.poll(() => placeholderIndex(second)).toBe(1)
    await page.mouse.up()
    await syncLV(page)

    await expect(second.locator('.block-children')).not.toHaveClass(/is-drop-target/)
    await expect.poll(() => names(first)).toEqual(['Alice'])
    await expect.poll(() => names(second)).toEqual(['Carol', 'Bob'])

    await awaitBlockShip(page)
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await page.getByRole('link', { name: 'Multi Row Move', exact: true }).click()
    await syncLV(page)

    await expect.poll(() => names(rows(page).nth(0))).toEqual(['Alice'])
    await expect.poll(() => names(rows(page).nth(2))).toEqual(['Carol', 'Bob'])
  })

  test('a row of another module takes no entry, and nothing moves', async ({ page }) => {
    await createPage(page, 'Multi Row Refuse', 'multi-row-refuse')
    const [first, other, second] = [rows(page).nth(0), rows(page).nth(1), rows(page).nth(2)]

    // Bob, the last entry, so the drag passes nothing in his own row
    await pickUpAndHold(page, entries(first).nth(1), entries(other).nth(0))
    // Sortable's placeholder never enters the row that does not take it
    await expect(other.locator('.block-children > .is-sorting')).toHaveCount(0)
    await page.mouse.up()
    await syncLV(page)

    await expect.poll(() => names(first)).toEqual(['Alice', 'Bob'])
    await expect.poll(() => names(second)).toEqual(['Carol'])
    await expect(entries(other)).toHaveCount(1)
  })

  // Sortable leaves the placeholder in the last row that took it, and the
  // move used to go there though the entry was released over a row that
  // does not take it.
  test('an entry carried over a row that takes it and released over one that does not stays', async ({ page }) => {
    await createPage(page, 'Multi Row Pass Over', 'multi-row-pass-over')
    const [first, other, second] = [rows(page).nth(0), rows(page).nth(1), rows(page).nth(2)]

    await pickUpAndHold(page, entries(first).nth(1), entries(second).nth(0))
    await expect.poll(() => placeholderIndex(second)).toBe(1)
    await holdOver(page, entries(other).nth(0))
    await expect(other.locator('.block-children > .is-sorting')).toHaveCount(0)
    await page.mouse.up()
    await syncLV(page)

    await expect.poll(() => names(first)).toEqual(['Alice', 'Bob'])
    await expect.poll(() => names(second)).toEqual(['Carol'])
    await expect(entries(other)).toHaveCount(1)
  })

  // A row with no entries takes one while it is dragged: a new row, and a
  // row whose last entry went and is wanted back.
  test('an empty row takes an entry, and takes it back after it left', async ({ page }) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Multi Row Empty')
    await page.getByLabel('URI').fill('multi-row-empty')
    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    await addEntry(page, rows(page).nth(0), 'COPY PASTE TEST', /^Team Member\b/, 'Alice')
    await addEntry(page, rows(page).nth(0), 'COPY PASTE TEST', /^Team Member\b/, 'Bob')
    await addRow(page, 'COPY PASTE TEST', 'Team Section')
    const [first, empty] = [rows(page).nth(0), rows(page).nth(1)]
    await expect(entries(empty)).toHaveCount(0)

    await pickUpAndHold(page, entries(first).nth(1), empty.locator('.block-children'))
    await expect(empty.locator('.block-children')).toHaveClass(/is-drop-target/)
    await expect.poll(() => placeholderIndex(empty)).toBe(0)
    await page.mouse.up()
    await syncLV(page)
    await expect.poll(() => names(first)).toEqual(['Alice'])
    await expect.poll(() => names(empty)).toEqual(['Bob'])

    // Back to the first row, and into the emptied row again
    await pickUpAndHold(page, entries(empty).nth(0), entries(first).nth(0))
    await expect.poll(() => placeholderIndex(first)).toBe(1)
    await page.mouse.up()
    await syncLV(page)
    await expect.poll(() => names(first)).toEqual(['Alice', 'Bob'])
    await expect(entries(empty)).toHaveCount(0)

    await pickUpAndHold(page, entries(first).nth(1), empty.locator('.block-children'))
    await expect.poll(() => placeholderIndex(empty)).toBe(0)
    await page.mouse.up()
    await syncLV(page)
    await expect.poll(() => names(first)).toEqual(['Alice'])
    await expect.poll(() => names(empty)).toEqual(['Bob'])

    await awaitBlockShip(page)
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await page.getByRole('link', { name: 'Multi Row Empty', exact: true }).click()
    await syncLV(page)

    await expect.poll(() => names(rows(page).nth(0))).toEqual(['Alice'])
    await expect.poll(() => names(rows(page).nth(1))).toEqual(['Bob'])
  })
})
