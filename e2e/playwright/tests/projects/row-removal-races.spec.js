import { test, expect } from '../../test-support/setupAuth'
import { serverLatency } from '../../test-support/latency'
import { syncLV, setEntryStatus } from '../../utils'

// Rows are numbered by position, and the server rebuilds the entry from each
// change's params. A change or Save sent before an add or a removal reached
// the browser must not undo it (#3157, `PendingRows`). A client's inline
// rows have date and media fields, whose inputs LiveView does not rename
// (inside phx-update="ignore", or held by a component): after a removal they
// must still name the row's new position, or they are sent as an extra row.

const table = page => page.locator('.subform--table')
const rows = page => table(page).locator('.subform-table-body > .subform-entry')
const titleOf = row => row.locator('input[name$="[title]"]')
const confirmedOf = row => row.getByRole('checkbox', { name: 'Confirmed' })

async function threeRows(page, { norwegian = false } = {}) {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Name' }).fill(`Row removal ${Date.now()}`)
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
  // All three rows first: on main, Add straight after typing was lost too
  // (the last test here).
  for (const count of [1, 2, 3]) {
    await table(page).getByRole('button', { name: norwegian ? 'Ny rad' : 'Add entry' }).click()
    await expect(rows(page)).toHaveCount(count)
    await syncLV(page)
  }
  for (const [index, title] of ['A', 'B', 'C'].entries()) await titleOf(rows(page).nth(index)).fill(title)
  await syncLV(page)
}

// What the server kept: save, reload and read the rows back.
async function saved(page) {
  // Saving an existing entry keeps the URL: wait for the write's reply too.
  await page.evaluate(() => {
    window.rowRemovalSaved = false
    window.addEventListener('phx:b:draft-reset', () => { window.rowRemovalSaved = true }, { once: true })
  })
  await page.keyboard.press('ControlOrMeta+s')
  await page.waitForFunction(() => window.rowRemovalSaved)
  await expect(page).toHaveURL(/\/admin\/projects\/clients\/update\/\d+/)
  await syncLV(page)
  await page.reload()
  await syncLV(page)
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
  const titles = await rows(page).locator('input[name$="[title]"]').evaluateAll(els => els.map(el => el.value))
  const confirmed = await rows(page).locator('input[type="checkbox"][name$="[confirmed]"]').evaluateAll(els => els.map(el => el.checked))
  const startsOn = await rows(page).locator('input[name$="[starts_on]"]').evaluateAll(els => els.map(el => el.value))
  return { titles, confirmed, startsOn }
}

test('a removal waiting for its reply leaves no extra row from date or media fields', async ({ page }) => {
  const latency = await serverLatency(page)
  await threeRows(page)
  // C's date input sits in Flatpickr's ignored subtree: its value must stay C's
  await rows(page).nth(2).locator('input[name$="[starts_on]"]').evaluate(el => el._flatpickr.setDate('2026-10-01', true))
  await syncLV(page)
  latency.set(1000)
  await rows(page).nth(1).getByRole('button', { name: 'Remove entry' }).click()
  latency.set(0)
  await expect(rows(page)).toHaveCount(2)
  await syncLV(page)
  const { titles, startsOn } = await saved(page)
  expect(titles).toEqual(['A', 'C'])
  expect(startsOn).toEqual(['', '2026-10-01'])
})

// The row hook holds clicks in the list until the removal's patch lands, so
// the tick itself may be held back; it must not corrupt the rows either way.
test('ticking the next row before the removal lands keeps the rows intact', async ({ page }) => {
  const latency = await serverLatency(page)
  await threeRows(page)
  latency.set(1000)
  await rows(page).nth(1).getByRole('button', { name: 'Remove entry' }).click()
  await confirmedOf(rows(page).nth(2)).focus()
  await page.keyboard.press('Space')
  latency.set(0)
  await expect(rows(page)).toHaveCount(2)
  await syncLV(page)
  expect((await saved(page)).titles).toEqual(['A', 'C'])
})

for (const persisted of [false, true]) test(`typing across a delayed removal keeps every character in ${persisted ? 'saved' : 'new'} rows`, async ({ page }) => {
  const latency = await serverLatency(page)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await threeRows(page, { norwegian: true })
  if (persisted) expect((await saved(page)).titles).toEqual(['A', 'B', 'C'])
  latency.set(1000)
  await rows(page).nth(1).getByRole('button', { name: 'Fjern element' }).click()
  await titleOf(rows(page).nth(2)).focus()
  await page.keyboard.press('ArrowRight')
  // Each pause exceeds the input debounce. Continue typing while removal
  // and validation replies arrive, so the focused input stays locked as
  // the surrounding row changes position (#3160).
  await page.keyboard.type('2345', { delay: 400 })
  latency.set(0)
  await expect(rows(page)).toHaveCount(2)
  await syncLV(page)
  expect((await saved(page)).titles).toEqual(['A', 'C2345'])
})

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
