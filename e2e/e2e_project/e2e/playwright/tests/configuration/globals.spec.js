import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function addGlobalVar(
  page,
  index,
  {
    key,
    label,
    type = 'String',
    instructions = '',
    placeholder = '',
    value = '',
  }
) {
  // Click on "Add entry"
  await page.getByRole('button', { name: 'Add entry' }).click()

  // Expand the newly added entry
  await page
    .locator(`#global_set_vars_${index}-edit div`)
    .filter({ hasText: 'key string' })
    .first()
    .click()

  // Fill in the key and label
  await page.locator(`#global_set_vars_${index}_key`).fill(key)
  await page.locator(`#global_set_vars_${index}_label`).fill(label)

  // If the type is something other than "String," select it
  if (type.toLowerCase() !== 'string') {
    await page
      .locator(`#global_set_vars_${index}_type-field-base`)
      .getByRole('button', { name: 'Select' })
      .click()
    await page.getByRole('button', { name: type }).click()
  }

  // Select 50% width
  await page
    .locator(`#global_set_vars_${index}_width-field-base`)
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: '50%' }).click()

  if (instructions) {
    await page
      .locator(`#global_set_vars_${index}_instructions`)
      .fill(instructions)
  }

  if (placeholder) {
    await page.getByLabel('Placeholder').fill(placeholder)
  }

  if (value) {
    await page.getByLabel(label).fill(value)
  }

  // Close the entry
  await page
    .locator(`#global_set_vars_${index}-edit div`)
    .filter({ hasText: `${key} ${type.toLowerCase()}` })
    .first()
    .click()
}

test('add global string', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByText('Globals').first().click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await page.getByLabel('Label').fill('Configuration')
  await page.getByLabel('Key').fill('config')

  // First "Add entry" (the string)
  await addGlobalVar(page, 0, {
    key: 'reservation',
    label: 'Reservation Link',
    type: 'String',
    instructions: 'URL to booking agent',
    placeholder: 'https://url.here.com',
  })

  // Second "Add entry" (the boolean)
  await addGlobalVar(page, 1, {
    key: 'boolean',
    label: 'Boolean value',
    type: 'Boolean',
    instructions: 'Instructions for boolean',
  })

  // Third "Add entry" (the color)
  await addGlobalVar(page, 2, {
    key: 'color',
    label: 'Color value',
    type: 'Color',
    instructions: 'Instructions for color',
  })

  await page.getByTestId('submit').click()
  await syncLV(page)
  await expect(page).toHaveURL('/admin/config/global_sets')
  await expect(page.getByText('3 variables in set')).toHaveCount(1)
})
