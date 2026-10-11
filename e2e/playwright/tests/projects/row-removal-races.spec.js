import { test, expect } from '../../test-support/setupAuth'
import { serverLatency } from '../../test-support/latency'
import { syncLV, setEntryStatus } from '../../utils'

// Rows are numbered by position, and the server rebuilds the entry from each
// change's params. A change or Save sent before an add or a removal reached
// the browser must not undo it (#3157, `PendingRows`). Removals with a held
// reply also need the date and media fields' names patched: that follow-up
// adds its own tests here.

const table = page => page.locator('.subform--table')
const rows = page => table(page).locator('.subform-table-body > .subform-entry')
const titleOf = row => row.locator('input[name$="[title]"]')

async function threeRows(page) {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Name' }).fill(`Row removal ${Date.now()}`)
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
  // All three rows first: on main, Add straight after typing was lost too
  // (the last test here).
  for (const count of [1, 2, 3]) {
    await table(page).getByRole('button', { name: 'Add entry' }).click()
    await expect(rows(page)).toHaveCount(count)
    await syncLV(page)
  }
  for (const [index, title] of ['A', 'B', 'C'].entries()) await titleOf(rows(page).nth(index)).fill(title)
  await syncLV(page)
}

// What the server kept: save, reload and read the rows back.
async function saved(page) {
  await page.keyboard.press('ControlOrMeta+s')
  await expect(page).toHaveURL(/\/admin\/projects\/clients\/update\/\d+/)
  await syncLV(page)
  await page.reload()
  await syncLV(page)
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
  const titles = await rows(page).locator('input[name$="[title]"]').evaluateAll(els => els.map(el => el.value))
  const confirmed = await rows(page).locator('input[type="checkbox"][name$="[confirmed]"]').evaluateAll(els => els.map(el => el.checked))
  return { titles, confirmed }
}

test('saving straight after a removal saves without the row', async ({ page }) => {
  await threeRows(page)
  await rows(page).nth(1).getByRole('button', { name: 'Remove entry' }).click()
  expect((await saved(page)).titles).toEqual(['A', 'C'])
})

test('Add straight after typing in a row adds a row and keeps the text', async ({ page }) => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Name' }).fill(`Row add ${Date.now()}`)
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
  await table(page).getByRole('button', { name: 'Add entry' }).click()
  await expect(rows(page)).toHaveCount(1)
  await syncLV(page)
  // Focus stays in the field: its change and the add leave together.
  await titleOf(rows(page).first()).fill('A')
  await table(page).getByRole('button', { name: 'Add entry' }).click()
  await expect(rows(page)).toHaveCount(2)
  await syncLV(page)
  await titleOf(rows(page).nth(1)).fill('B')
  await syncLV(page)
  expect((await saved(page)).titles).toEqual(['A', 'B'])
})

// Prices are plain text fields, so this covers the removal itself.
test('typing in the next row before a removal lands keeps the removal and the text', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.goto('/admin/prices/price_categories/create')
  await syncLV(page)
  await setEntryStatus(page, 'published')
  await page.locator('#price_category_title').fill(`Removal race ${Date.now()}`)
  const prices = page.locator('.subform-entry')
  const add = page.locator('.add-entry-button')
  await add.click()
  await expect(prices).toHaveCount(2)
  await syncLV(page)
  await add.click()
  await expect(prices).toHaveCount(3)
  await syncLV(page)
  for (const [index, title] of ['A', 'B', 'C'].entries()) {
    await prices.nth(index).getByRole('textbox', { name: 'Title', includeHidden: true }).fill(title)
    await prices.nth(index).getByRole('textbox', { name: 'Price' }).fill(`kr ${index + 1}00,-`)
  }
  await syncLV(page)

  // The removal's reply is held: the typing is sent while the browser still
  // lists B, and must not bring it back
  latency.set(1000)
  await prices.nth(1).getByRole('button', { name: 'Remove entry' }).click()
  await prices.nth(2).getByRole('textbox', { name: 'Title', includeHidden: true }).press('End')
  await page.keyboard.type('2')
  latency.set(0)
  await expect(prices).toHaveCount(2)
  await syncLV(page)

  await page.keyboard.press('ControlOrMeta+s')
  await expect(page).toHaveURL(/\/admin\/prices\/price_categories\/update\/\d+/)
  await syncLV(page)
  await page.reload()
  await syncLV(page)
  const titles = await prices.evaluateAll(rows => rows.map(row => row.querySelector('input[name$="[title]"]').value))
  expect(titles).toEqual(['A', 'C2'])
})
