import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Hovering a field offers the "Add note" button beside its label
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
    row.querySelectorAll(':scope > label > :not(span), :scope > :not(label, .field-note-add)').forEach((el, i) => {
      boxes[`${i} ${el.className || el.tagName}`] = box(el)
    })
    boxes.control = box(w.querySelector(':scope > .field-base'))
    // The count of open notes is the row's ::after, which has no box of its
    // own: it starts where the label (and the button, when offered) end.
    if (row.hasAttribute('data-note-count')) {
      const end = el => el ? el.getBoundingClientRect().right + parseFloat(getComputedStyle(el).marginRight) : 0
      const label = row.querySelector(':scope > label')
      boxes['note count starts at'] = round(Math.max(end(label), end(row.querySelector(':scope > .field-note-add'))))
    }
    return boxes
  })

async function expectStillOnHover(page, wrapper, target, hover = {}) {
  await wrapper.scrollIntoViewIfNeeded()
  await page.mouse.move(2, 2)
  await expect(wrapper.locator(':scope > .label-wrapper > .field-note-add')).toHaveCount(0)
  const before = await rowBoxes(wrapper)

  await target.hover(hover)
  await expect(wrapper.locator(':scope > .label-wrapper > .field-note-add')).toBeVisible()
  expect(await rowBoxes(wrapper)).toEqual(before)
}

test('the note button beside a label moves nothing in the label row', async ({ page, secondUserPage }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await secondUserPage.setViewportSize({ width: 1440, height: 1000 })

  await page.goto('/admin/projects/projects/update/1')
  await syncLV(page)

  // A text input, a rich-text field and a select
  const title = fieldWrapper(page, 'project[title]')
  await expectStillOnHover(page, title, title.locator('input'))
  const introduction = fieldWrapper(page, 'project[introduction]')
  await expectStillOnHover(page, introduction, introduction.locator('.field-base'))
  const client = fieldWrapper(page, 'project[client_id]')
  await expectStillOnHover(page, client, client.locator('.field-base'))

  // A field with an open note: the count on its label stays put as well
  await title.locator('input').hover()
  await title.locator('.field-note-add').click()
  const composer = page.locator('.notes-panel .note-composer').getByRole('textbox')
  await composer.pressSequentially('Is the title final?')
  await composer.press('Enter')
  await syncLV(page)
  await expect(title.locator(':scope > .label-wrapper')).toHaveAttribute('data-note-count', '1')
  await client.locator('.field-base').hover()
  await expectStillOnHover(page, title, title.locator('input'))

  // A field with another editor's presence avatar in its label
  await secondUserPage.goto('/admin/projects/projects/update/1')
  await syncLV(secondUserPage)
  await page.getByLabel('Title', { exact: true }).click()
  const theirs = fieldWrapper(secondUserPage, 'project[title]')
  await expect(theirs.locator('.field-presence-user')).toHaveCount(1)
  // Their field is locked here, so the pointer meets the wrapper, not the input.
  const control = await theirs.locator(':scope > .field-base').boundingBox()
  const wrapperBox = await theirs.boundingBox()
  await expectStillOnHover(secondUserPage, theirs, theirs, {
    position: { x: 40, y: control.y - wrapperBox.y + control.height / 2 },
  })

  // A textarea, in the meta drawer
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.getByRole('button', { name: 'Meta', exact: true }).click()
  const description = fieldWrapper(page, 'page[meta_description]')
  await expect(description.locator('textarea')).toBeVisible()
  await expectStillOnHover(page, description, description.locator('textarea'))
})
