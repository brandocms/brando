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

const openServices = async page => {
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('button', { name: 'Services' }).click()
}

const save = async page => {
  const saveState = page.locator('.draft-save-state').first()
  await page.getByTestId('submit').click()
  await expect(saveState).toHaveAttribute('data-state', 'clean', { timeout: 15000 })
}

// A saved service with nothing else changed is rendered from its data, so a
// blank row would not come back in a render: the insert must send nothing
test("a row inserted into a saved service's alternate names keeps every value through typing and saving", async ({ page }) => {
  await page.goto('/admin/config/identity')
  await syncLV(page)
  await openServices(page)
  await page.getByRole('button', { name: 'Add entry', exact: true }).click()

  const created = page.locator('.summary-entry').last()
  await created.getByRole('textbox', { name: 'Name', exact: true }).fill('Consulting')
  const createdNames = created.locator('.string-list[id$="_alternate_names"]')
  await addValue(createdNames, 'Advice', 2)
  await addValue(createdNames, 'Guidance', 3)
  await syncLV(page)
  await save(page)

  await page.reload()
  await syncLV(page)
  await openServices(page)
  const service = page.locator('.summary-entry').filter({ hasText: 'Consulting' })
  await service.getByRole('button', { name: 'Edit', exact: true }).click()
  const names = service.locator('.string-list[id$="_alternate_names"]')
  await expectValues(names, ['Advice', 'Guidance', ''])

  // Above the second value
  await names.locator('.string-list-row').nth(1).hover()
  await names.locator('.string-list-row').nth(1).locator('.string-list-insert').click()
  await expect(values(names)).toHaveCount(4)
  await expect(values(names).nth(1)).toBeFocused()

  // Past the debounce: a render of the list without the blank row would
  // land on the shifted rows
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Advice', '', 'Guidance', ''])

  await page.keyboard.type('Counsel')
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Advice', 'Counsel', 'Guidance', ''])
  await save(page)

  await page.reload()
  await syncLV(page)
  await openServices(page)
  const saved = page.locator('.summary-entry').filter({ hasText: 'Consulting' })
  await saved.getByRole('button', { name: 'Edit', exact: true }).click()
  await expectValues(saved.locator('.string-list[id$="_alternate_names"]'), ['Advice', 'Counsel', 'Guidance', ''])
})

const openContent = async page => {
  await page.getByRole('navigation', { name: 'Sections' }).getByRole('button', { name: 'Content' }).click()
}

// A saved service named `name` with `values` as its alternate names, open
// for editing after a reload
const savedService = async (page, name, values) => {
  await page.goto('/admin/config/identity')
  await syncLV(page)
  await openServices(page)
  await page.getByRole('button', { name: 'Add entry', exact: true }).click()
  const created = page.locator('.summary-entry').last()
  await created.getByRole('textbox', { name: 'Name', exact: true }).fill(name)
  const createdNames = created.locator('.string-list[id$="_alternate_names"]')
  for (const [index, value] of values.entries()) await addValue(createdNames, value, index + 2)
  await syncLV(page)
  await save(page)

  await page.reload()
  await syncLV(page)
  await openServices(page)
  const service = page.locator('.summary-entry').filter({ hasText: name })
  await service.getByRole('button', { name: 'Edit', exact: true }).click()
  const names = service.locator('.string-list[id$="_alternate_names"]')
  await expectValues(names, [...values, ''])
  return names
}

const insertAbove = async (list, index) => {
  const row = list.locator('.string-list-row').nth(index)
  await row.hover()
  await row.locator('.string-list-insert').click()
}

// A patch of the form by another field's change renders the list from the
// server's values, without the rows inserted in the browser alone
const changeIdentityName = async (page, value) => {
  await openContent(page)
  await page.getByRole('textbox', { name: 'Name', exact: true }).fill(value)
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await openServices(page)
}

test('an inserted row keeps its place when another field patches the form before anything is typed in it', async ({ page }) => {
  const names = await savedService(page, 'Mentoring', ['Advice', 'Guidance'])

  await insertAbove(names, 1)
  await expectValues(names, ['Advice', '', 'Guidance', ''])

  await changeIdentityName(page, 'Patched identity')
  await expectValues(names, ['Advice', '', 'Guidance', ''])

  await values(names).nth(1).click()
  await page.keyboard.type('Counsel')
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Advice', 'Counsel', 'Guidance', ''])
  await save(page)

  await page.reload()
  await syncLV(page)
  await openServices(page)
  const saved = page.locator('.summary-entry').filter({ hasText: 'Mentoring' })
  await saved.getByRole('button', { name: 'Edit', exact: true }).click()
  await expectValues(saved.locator('.string-list[id$="_alternate_names"]'), ['Advice', 'Counsel', 'Guidance', ''])
})

test('two inserted rows keep their places when another field patches the form, and typing lands in each', async ({ page }) => {
  const names = await savedService(page, 'Tutoring', ['Advice', 'Guidance', 'Support'])

  await insertAbove(names, 2)
  await insertAbove(names, 0)
  await expectValues(names, ['', 'Advice', 'Guidance', '', 'Support', ''])

  await changeIdentityName(page, 'Patched twice')
  await expectValues(names, ['', 'Advice', 'Guidance', '', 'Support', ''])

  await values(names).nth(3).click()
  await page.keyboard.type('Help')
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['', 'Advice', 'Guidance', 'Help', 'Support', ''])

  await values(names).nth(0).click()
  await page.keyboard.type('Coaching')
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
  await expectValues(names, ['Coaching', 'Advice', 'Guidance', 'Help', 'Support', ''])
  await save(page)

  await page.reload()
  await syncLV(page)
  await openServices(page)
  const saved = page.locator('.summary-entry').filter({ hasText: 'Tutoring' })
  await saved.getByRole('button', { name: 'Edit', exact: true }).click()
  await expectValues(saved.locator('.string-list[id$="_alternate_names"]'), ['Coaching', 'Advice', 'Guidance', 'Help', 'Support', ''])
})

// Another form on the page, such as an entry's notes drawer, submitted on
// its own: the identity is not saved, so the inserted row stays pending
const submitAnotherForm = async page => {
  await page.evaluate(() => {
    const form = document.createElement('form')
    form.addEventListener('submit', event => event.preventDefault())
    document.body.append(form)
    form.requestSubmit()
    form.remove()
  })
}

test('an inserted row keeps its place when another form on the page is submitted', async ({ page }) => {
  const names = await savedService(page, 'Coaching', ['Advice', 'Guidance'])

  await insertAbove(names, 1)
  await expectValues(names, ['Advice', '', 'Guidance', ''])

  await submitAnotherForm(page)
  await changeIdentityName(page, 'Patched after a note')
  await expectValues(names, ['Advice', '', 'Guidance', ''])
})

// The identity's name changed without moving focus, so the patch arrives
// while the focus is where the editor left it
const changeIdentityNameInPlace = async (page, value) => {
  await page.evaluate(value => {
    const input = document.querySelector('input[name$="[name]"]:not([name*="[services]"])')
    input.value = value
    input.dispatchEvent(new Event('input', { bubbles: true }))
  }, value)
  await page.waitForTimeout(STRING_LIST_DEBOUNCE_MS + 50)
  await syncLV(page)
}

test("a patch leaves the focus on an inserted row's Remove button", async ({ page }) => {
  const names = await savedService(page, 'Advising', ['Advice', 'Guidance'])

  await insertAbove(names, 1)
  await expect(values(names).nth(1)).toBeFocused()
  await page.keyboard.press('Tab')
  const remove = names.locator('.string-list-row').nth(1).getByRole('button', { name: 'Remove row' })
  await expect(remove).toBeFocused()

  await changeIdentityNameInPlace(page, 'Patched in place')
  await expect(remove).toBeFocused()

  await page.keyboard.press('Space')
  await expectValues(names, ['Advice', 'Guidance', ''])
})
