import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// An inline subform (`inputs_for … style :inline`) is a table: one line per
// entry under one row of column headings. The client form's "Inline fields"
// tab holds one of every input that fits on a line (E2eProject.Projects.InlineRow).

const table = page => page.locator('.subform--table')
const rows = page => table(page).locator('.subform-table-body > .subform-entry')
const titleOf = row => row.locator('input[name$="[title]"]')

// Every column cell of a row, including the empty cell of a hidden field
const cellsOf = row => row.locator('.subform-fields > .brando-input:not([data-component="hidden"])')

async function openInlineFields(page) {
  await page.getByRole('button', { name: 'Inline fields' }).click()
  await syncLV(page)
}

// Waits for the row itself: the click's reply comes before the form sends
// the subform its new rows. (Two quick adds both land; see the double click
// test below.)
async function addRow(page) {
  const count = await rows(page).count()
  await table(page).getByRole('button', { name: 'Add entry' }).click()
  await expect(rows(page)).toHaveCount(count + 1)
  await syncLV(page)
}

test('inline subform rows are one line under aligned headings', async ({ page }) => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await openInlineFields(page)

  await expect(table(page).locator('.subform-empty')).toBeVisible()
  await addRow(page)
  await addRow(page)
  await expect(rows(page)).toHaveCount(2)

  const headings = table(page).locator('.subform-table-head .brando-input')
  const headingCount = await headings.count()
  expect(headingCount).toBeGreaterThan(15)

  for (const row of await rows(page).all()) {
    // One line: a 32px control, its padding and the row's rule
    const rowBox = await row.boundingBox()
    expect(rowBox.height).toBeLessThanOrEqual(48)

    // Each heading sits over its column, including Size, which is hidden
    // until the kind is an exhibition and leaves an empty cell
    const cells = cellsOf(row)
    await expect(cells).toHaveCount(headingCount)
    for (let i = 0; i < headingCount; i++) {
      const heading = await headings.nth(i).boundingBox()
      const cell = await cells.nth(i).boundingBox()
      expect(Math.abs(heading.x - cell.x)).toBeLessThanOrEqual(1)
      expect(Math.abs(heading.width - cell.width)).toBeLessThanOrEqual(1)
    }
  }

  await expect(rows(page).first().locator('.brando-input[data-hidden]')).toHaveCount(1)
})

test('entries are inserted between rows, removed, and saved in order', async ({ page }) => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Name' }).fill('Inline client')
  await openInlineFields(page)

  await addRow(page)
  await addRow(page)
  await titleOf(rows(page).nth(0)).fill('First')
  await titleOf(rows(page).nth(1)).fill('Third')
  await syncLV(page)

  // Insert sits on the line above its row
  await rows(page).nth(1).hover()
  await rows(page).nth(1).getByRole('button', { name: 'Insert entry' }).click()
  await syncLV(page)
  await expect(rows(page)).toHaveCount(3)
  await expect(titleOf(rows(page).nth(0))).toHaveValue('First')
  await expect(titleOf(rows(page).nth(1))).toHaveValue('New row')
  await expect(titleOf(rows(page).nth(2))).toHaveValue('Third')
  await titleOf(rows(page).nth(1)).fill('Second')

  // A required field's error shows inside its row
  await addRow(page)
  await titleOf(rows(page).nth(3)).fill('')
  await syncLV(page)
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('dialog').getByRole('button', { name: 'OK' }).click()
  await expect(rows(page).nth(3).locator('.field-error')).toBeVisible()

  await rows(page).nth(3).hover()
  await rows(page).nth(3).getByRole('button', { name: 'Remove entry' }).click()
  await syncLV(page)
  await expect(rows(page)).toHaveCount(3)

  await page.getByTestId('submit').click()
  await syncLV(page)

  await page.getByRole('link', { name: 'Inline client', exact: true }).click()
  await syncLV(page)
  await openInlineFields(page)
  await expect(rows(page)).toHaveCount(3)
  await expect(titleOf(rows(page).nth(0))).toHaveValue('First')
  await expect(titleOf(rows(page).nth(1))).toHaveValue('Second')
  await expect(titleOf(rows(page).nth(2))).toHaveValue('Third')
})

// The colour picker holds a change back for a moment while it is dragged.
// A save pressed in that moment used to read the colour from before; it now
// asks the picker for it first (assets/src/hooks/Form/pendingChange.js).
test('a colour picked just before saving is saved', async ({ page }) => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Name' }).fill('Colour client')
  await openInlineFields(page)
  await addRow(page)

  await rows(page).first().locator('.circle-and-hex').click()
  const area = page.locator('.picker_sl').last()
  await expect(area).toBeVisible()
  const box = await area.boundingBox()
  await page.mouse.click(box.x + box.width * 0.8, box.y + box.height * 0.3)
  // saved at once, inside the picker's moment
  await page.keyboard.press('ControlOrMeta+s')

  await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
  await syncLV(page)
  await page.reload()
  await syncLV(page)
  await openInlineFields(page)
  await expect(rows(page).first().locator('input[type="hidden"][name$="[color]"]')).toHaveValue(/^#[0-9a-f]{6}$/i)
})

// Two quick clicks on Add entry. LiveView's client drops a click on a button
// whose previous click is still unanswered, so a double click's second click
// lands just after the first one's reply, before the form has sent the subform
// its new row (the server answers the click first and updates the form after).
// Each add must build on the form's latest rows, not on the copy the subform
// last rendered with, or one of the two is lost.
async function doubleAdd(page) {
  await table(page).getByRole('button', { name: 'Add entry' }).evaluate(button => new Promise(resolve => {
    const observer = new MutationObserver(() => {
      if (button.hasAttribute('data-phx-ref-src')) return
      observer.disconnect()
      button.click()
      resolve()
    })
    observer.observe(button, { attributes: true, attributeFilter: ['data-phx-ref-src'] })
    button.click()
  }))
  await syncLV(page)
}

test('a double click on Add entry adds two rows', async ({ page }) => {
  await page.goto('/admin/projects/clients/create')
  await syncLV(page)
  await openInlineFields(page)

  await expect(table(page).locator('.subform-empty')).toBeVisible()
  await doubleAdd(page)
  await expect(rows(page)).toHaveCount(2)
  await doubleAdd(page)
  await expect(rows(page)).toHaveCount(4)
})
