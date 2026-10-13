import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A palette select's options are HTML labels: a stack of tiny swatches, then
// "[namespace] name" (`Brando.Content.Container.get_palettes/2`, and the same
// markup in applications). The stack stays inside the field, before the
// name, and on the name's line in the options dialog.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const box = async locator => {
  const b = await locator.boundingBox()
  expect(b).not.toBeNull()
  return b
}

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('palette swatches stay inside the select field and on the label line', async ({ page }) => {
  await factory(page, 'Brando.Content.Palette', {
    name: 'Autumn',
    key: 'autumn',
    namespace: 'articles',
    status: 'published',
    colors: [
      { name: 'Rust', key: 'rust', hex_value: '#b5532a' },
      { name: 'Moss', key: 'moss', hex_value: '#5d6b2f' },
      { name: 'Sand', key: 'sand', hex_value: '#e2cfa4' },
      { name: 'Ink', key: 'ink', hex_value: '#1d2433' },
    ],
  })

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/config/content/containers/update/1')
  await syncLV(page)

  const field = page.locator(".multiselect[data-select-input$='palette_id']")
  await field.getByRole('button', { name: 'Velg' }).click()

  const option = page.locator('.select-modal .options-option').filter({ hasText: 'Autumn' })
  await expect(option).toBeVisible()

  // In the dialog: the swatches sit on the label's line, before the name
  const optionStack = await box(option.locator('.circle-stack'))
  const optionName = await box(option.locator('.text-mono'))
  expect(optionStack.width).toBeGreaterThan(0)
  expect(Math.abs(optionStack.y + optionStack.height / 2 - (optionName.y + optionName.height / 2))).toBeLessThan(4)
  expect(optionStack.x + optionStack.width).toBeLessThanOrEqual(optionName.x)

  await option.click()
  await expect(field.locator('.select-label .text-mono')).toContainText('Autumn')

  // In the field: every swatch inside the field's border, none over the name
  const fieldBox = await box(field)
  const name = await box(field.locator('.select-label .text-mono'))
  const swatches = field.locator('.select-label .circle.tiny')
  await expect(swatches).toHaveCount(4)

  for (const swatch of await swatches.all()) {
    const b = await box(swatch)
    expect(b.x).toBeGreaterThanOrEqual(fieldBox.x)
    expect(b.x + b.width).toBeLessThanOrEqual(name.x)
  }
})
