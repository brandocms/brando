import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// phx-debounce on a string list's inputs (`Input.input/1`, `:string_list`)
const STRING_LIST_DEBOUNCE_MS = 300

const values = list => list.locator('input.string-list-input')

const expectValues = (list, expected) =>
  expect.poll(() => values(list).evaluateAll(inputs => inputs.map(input => input.value))).toEqual(expected)

// Each value typed into the empty row becomes a row once the server has it
const addValue = async (list, value, count) => {
  await list.locator('.string-list-add input').fill(value)
  await expect(values(list)).toHaveCount(count)
}

test("a row inserted into a service's alternate names keeps every value through typing and saving", async ({ page }) => {
  await page.goto('/admin/config/identity')
  await syncLV(page)

  await page.getByRole('tab', { name: 'Services' }).click()
  await page.getByRole('button', { name: 'Add entry', exact: true }).click()

  const service = page.locator('.summary-entry').last()
  await service.getByRole('textbox', { name: 'Name' }).fill('Consulting')

  const names = service.locator('.string-list[id$="_alternate_names"]')
  await addValue(names, 'Advice', 2)
  await addValue(names, 'Guidance', 3)
  await syncLV(page)

  // Above the second value
  await names.locator('.string-list-row').nth(1).hover()
  await names.locator('.string-list-row').nth(1).locator('.string-list-insert').click()
  await expect(values(names)).toHaveCount(4)
  await expect(values(names).nth(1)).toBeFocused()

  // An insert sends nothing here: past the debounce a render of the list
  // without the blank row would land on the shifted rows
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Advice', '', 'Guidance', ''])

  await page.keyboard.type('Counsel')
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Advice', 'Counsel', 'Guidance', ''])

  const saveState = page.locator('.draft-save-state').first()
  await page.getByTestId('submit').click()
  await expect(saveState).toHaveAttribute('data-state', 'clean', { timeout: 15000 })

  await page.reload()
  await syncLV(page)
  await page.getByRole('tab', { name: 'Services' }).click()
  const saved = page.locator('.summary-entry').filter({ hasText: 'Consulting' })
  await saved.getByRole('button', { name: 'Edit', exact: true }).click()

  await expectValues(saved.locator('.string-list[id$="_alternate_names"]'), ['Advice', 'Counsel', 'Guidance', ''])
})
