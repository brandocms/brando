import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A `:checkbox` input without `text:` draws its circle on an empty label,
// which used to centre it on a line of no height, over the field's label.
// InlineRow's `Confirmed` is one (its `:locked` form).
test('a checkbox without text draws its circle below the field label', async ({ page }) => {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema: 'E2eProject.Projects.InlineRow', attributes: { title: 'Opening night', status: 'published', confirmed: true }, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  const { id } = await response.json()

  await page.goto(`/admin/projects/inline_rows/update/${id}`)
  await syncLV(page)

  const field = page.locator('#inline_row_confirmed-field-wrapper')
  const label = await field.locator(':scope > .label-wrapper').boundingBox()
  // The circle is absolutely positioned in the check wrapper
  const circle = await field.locator('.check-wrapper label').evaluate(el => ({
    top: el.parentElement.getBoundingClientRect().top + parseFloat(getComputedStyle(el, '::before').top),
  }))

  expect(circle.top).toBeGreaterThanOrEqual(label.y + label.height)

  // Only the circle takes a click, not the empty width beside it
  const checkbox = await field.locator('.check-wrapper label').boundingBox()
  expect(checkbox.width).toBeLessThan(60)
})
