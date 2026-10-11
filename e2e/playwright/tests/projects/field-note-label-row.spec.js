import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Hovering a label offers the "Add note" button at the row's far right
// (assets/src/Notes). Offering it must not move anything in the label row or
// push the control down, whatever the field and whoever else is in it.

const fieldWrapper = (page, name) =>
  page.locator('.field-wrapper').filter({ has: page.locator(`:scope > .label-wrapper > [data-field-presence="${name}"]`) })

// The label row's boxes, and the control's, rounded to a hundredth.
const rowBoxes = wrapper =>
  wrapper.evaluate(w => {
    const round = n => Math.round(n * 100) / 100
    const box = el => {
      const b = el.getBoundingClientRect()
      return [b.x, b.y, b.width, b.height].map(round).join(', ')
    }
    const row = w.querySelector(':scope > .label-wrapper')
    const boxes = { 'label row': box(row), label: box(row.querySelector(':scope > label')) }
    const text = row.querySelector(':scope > label > span')
    if (text) boxes['label text'] = box(text)
    row.querySelectorAll(':scope > label > :not(span), :scope > :not(label, .field-note-add, .field-note-slot)').forEach((el, i) => {
      boxes[`${i} ${el.className || el.tagName}`] = box(el)
    })
    boxes.control = box(w.querySelector(':scope > .field-base'))
    return boxes
  })

async function expectStillOnHover(page, wrapper) {
  await wrapper.scrollIntoViewIfNeeded()
  await page.mouse.move(2, 2)
  await page.evaluate(() => document.activeElement?.blur())
  const before = await rowBoxes(wrapper)

  await wrapper.locator(':scope > .label-wrapper').hover()
  await expect(wrapper.locator(':scope > .label-wrapper .field-note-add')).toHaveCSS('opacity', '1')
  expect(await rowBoxes(wrapper)).toEqual(before)
}

test('the note button beside a label moves nothing in the label row', async ({ page, secondUserPage }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await secondUserPage.setViewportSize({ width: 1440, height: 1000 })

  await page.goto('/admin/projects/projects/update/1')
  await syncLV(page)

  // A text input, a rich-text field and a select
  const title = fieldWrapper(page, 'project[title]')
  await expectStillOnHover(page, title)
  const introduction = fieldWrapper(page, 'project[introduction]')
  await expectStillOnHover(page, introduction)
  const client = fieldWrapper(page, 'project[client_id]')
  await expectStillOnHover(page, client)

  // A field with an open note: the count on its label stays put as well
  await title.locator(':scope > .label-wrapper').hover()
  await title.locator('.field-note-add').click()
  const composer = page.locator('.notes-panel .note-composer').getByRole('textbox')
  await composer.pressSequentially('Is the title final?')
  await composer.press('Enter')
  await syncLV(page)
  await expect(title.locator(':scope > .label-wrapper')).toHaveAttribute('data-note-count', '1')
  await client.locator('.field-base').hover()
  await expectStillOnHover(page, title)

  // A field with another editor's presence avatar in its label
  await secondUserPage.goto('/admin/projects/projects/update/1')
  await syncLV(secondUserPage)
  await page.getByLabel('Title', { exact: true }).click()
  const theirs = fieldWrapper(secondUserPage, 'project[title]')
  await expect(theirs.locator('.field-presence-user')).toHaveCount(1)
  // A locked input still offers notes through its label.
  await expectStillOnHover(secondUserPage, theirs)

  // A textarea, in the meta drawer
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.getByRole('button', { name: 'Meta', exact: true }).click()
  const description = fieldWrapper(page, 'page[meta_description]')
  await expect(description.locator('textarea')).toBeVisible()
  await expectStillOnHover(page, description)
})


test('a compact variable keeps Add link still and offers notes at the far right only after label hover', async ({ page }) => {
  await page.goto('/admin/pages/update/3')
  await syncLV(page)
  const label = page.locator('.variable.link .label-wrapper').filter({ hasText: 'Call to action' }).first()
  const wrapper = label.locator('..')
  const addLink = wrapper.getByRole('button', { name: 'Add link', exact: true })
  await addLink.scrollIntoViewIfNeeded()
  await page.mouse.move(2, 2)
  await page.evaluate(() => document.activeElement?.blur())
  const before = await addLink.boundingBox()
  await addLink.hover()
  await expect(label.locator('.field-note-add')).toHaveCount(0)
  expect(await addLink.boundingBox()).toEqual(before)

  await label.hover()
  const note = label.getByRole('button', { name: 'Add note', exact: true })
  await expect(note).toHaveCSS('opacity', '1')
  expect(await addLink.boundingBox()).toEqual(before)
  const [action, field] = await Promise.all([note.boundingBox(), wrapper.boundingBox()])
  expect(Math.abs(action.x + action.width - field.x - field.width)).toBeLessThan(1)
  // Crossing the control on the way to the far-right icon must not hide it.
  await addLink.hover()
  await expect(note).toHaveCSS('opacity', '1')
  await note.click()
  await expect(page.locator('.notes-panel .note-composer')).toContainText('Call to action')
})

test('validation errors leave the far-right note action clear and clickable', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  const title = fieldWrapper(page, 'page[title]')
  await page.getByLabel('Title', { exact: true }).fill('')
  await page.getByLabel('Title', { exact: true }).blur()
  const error = title.locator(':scope > .label-wrapper > .field-errors')
  await expect(error).not.toBeEmpty()
  await title.locator(':scope > .label-wrapper').hover()
  const note = title.locator('.field-note-add')
  await expect(note).toHaveCSS('opacity', '1')
  const [errorBox, noteBox] = await Promise.all([error.boundingBox(), note.boundingBox()])
  expect(errorBox.x + errorBox.width).toBeLessThanOrEqual(noteBox.x)
  await note.click()
  await expect(page.locator('.notes-panel .note-composer')).toContainText('Title')
})

test('a field note action stays reachable across a LiveView patch while the pointer remains in its row', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  const vars = page.locator('.subform--vars')
  const label = vars.locator(':scope > .label-wrapper')
  const add = vars.getByRole('button', { name: 'Add entry', exact: true })
  await page.evaluate(() => document.activeElement?.blur())
  await label.hover()
  const note = label.locator('.field-note-add')
  await expect(note).toHaveCSS('opacity', '1')
  await add.hover()
  const before = await vars.locator('.vars-row').count()
  // Programmatic click leaves focus outside the field, so focus-within cannot
  // hide a lost hover state when the server patches the label's ignored slot.
  await add.evaluate(el => el.click())
  await expect(vars.locator('.vars-row')).toHaveCount(before + 1)
  await expect(note).toHaveCSS('opacity', '1')
  await note.click()
  await expect(page.locator('.notes-panel .note-composer')).toContainText('Page variables')
})
