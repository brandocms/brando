import { test, expect } from '../../test-support/setupAuth'

// A `:string_list` with `sync_insert`, in a form that renders its blank rows
// back (`E2eProjectAdmin.StringListLive`, as the Sites screen's languages)
const list = page => page.locator('#string-list-form .string-list')
const values = page => list(page).locator('input.string-list-input')
const row = (page, index) => list(page).locator('.string-list-row').nth(index)

const expectValues = (page, expected) =>
  expect.poll(() => values(page).evaluateAll(inputs => inputs.map(input => input.value))).toEqual(expected)

// Clicks a row's insert button and says whether the form's change was sent
// in the same task: LiveView marks the form loading as it sends, and a
// debounced change would not have been sent yet
const insertAbove = (page, index) =>
  row(page, index)
    .locator('.string-list-insert')
    .evaluate(button => {
      button.click()
      return button.closest('form').classList.contains('phx-change-loading')
    })

test.beforeEach(async ({ page }) => {
  await page.goto('/admin/__string_list')
  await expectValues(page, ['alpha', 'beta', ''])
  await expect(page.locator('#change-count')).toHaveText('0')
})

test('an inserted row is sent at once, before anything is typed in it', async ({ page }) => {
  expect(await insertAbove(page, 1)).toBe(true)

  await expect(page.locator('#change-count')).toHaveText('1')
  await expect(page.locator('#received-names')).toHaveText('["alpha","","beta",""]')
  await expectValues(page, ['alpha', '', 'beta', ''])
  await expect(values(page).nth(1)).toBeFocused()
})

test('a value still waiting for its debounce is kept when a row is inserted above it', async ({ page }) => {
  await values(page).nth(0).fill('alpha edited')
  expect(await insertAbove(page, 0)).toBe(true)

  await expect(page.locator('#received-names')).toHaveText('["","alpha edited","beta",""]')
  await expectValues(page, ['', 'alpha edited', 'beta', ''])

  await values(page).nth(0).fill('first')
  await expect(page.locator('#received-names')).toHaveText('["first","alpha edited","beta",""]')
  await expectValues(page, ['first', 'alpha edited', 'beta', ''])
})
