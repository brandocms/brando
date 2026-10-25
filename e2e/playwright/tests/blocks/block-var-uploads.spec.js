import { test, expect } from '../../test-support/setupAuth'
import { syncLV, mediaMenu, mediaMenuButton } from '../../utils'

async function createVarPage(page, title) {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
  await expect(page.locator('.module-picker-namespace.active')).toContainText('07 VAR UPLOAD TEST')
  await page.getByRole('button', { name: 'Image and File Vars' }).click()
  await syncLV(page)
}

function mediaField(page, type) {
  return page.locator(`.media-field[data-kind="block_var"][id$="-${type}-media"]`)
}

for (const type of ['image', 'file']) {
  test(`${type} var removal leaves a usable upload field`, async ({ page }) => {
    test.setTimeout(120000)
    await createVarPage(page, `Var ${type} Remove Test`)
    const field = mediaField(page, type)
    await field.locator('input[type="file"]').setInputFiles(type === 'image' ? './fixtures/image.jpg' : './fixtures/test.pdf')
    await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 20000 })
    await mediaMenu(field, 'Configure')
    const modal = page.locator(`[id$="${type}-config"]:visible`)
    await modal.getByRole('button', { name: 'Remove', exact: true }).click()
    await modal.getByRole('button', { name: 'Done', exact: true }).click()
    await expect(modal).not.toBeVisible()
    await expect(field).not.toHaveAttribute('data-asset-id', /\d+/)
    await expect(mediaMenuButton(field)).toHaveText('Add')
    await mediaMenuButton(field).click()
    await expect(field.locator('.media-field-menu').getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
    await expect(field.locator('.media-field-menu').getByRole('button', { name: `Select ${type}`, exact: true })).toBeVisible()
  })
}

// Half-width media variables are one line on a desktop. In a phone's half of
// a row the menu goes under the details and the label above the field, so
// the Add button never covers the details or leaves its cell.
test('half-width media variables keep their Add button clear of their details', async ({ page }) => {
  await createVarPage(page, 'Var Narrow Layout Test')
  const layout = () =>
    page.evaluate(() =>
      ['image', 'file'].map(type => {
        const field = document.querySelector(`.media-field[data-kind="block_var"][id$="-${type}-media"]`)
        const cell = field.closest('.variable').getBoundingClientRect()
        const button = field.querySelector('.media-action-menu > .media-button').getBoundingClientRect()
        const copy = field.querySelector('.media-field-copy').getBoundingClientRect()
        const overlaps = button.left < copy.right && copy.left < button.right && button.top < copy.bottom && copy.top < button.bottom
        return { type, overlaps, inside: button.right <= cell.right + 0.5, below: button.top >= copy.bottom - 0.5 }
      })
    )

  for (const field of await layout()) {
    expect(field.overlaps, field.type).toBe(false)
    expect(field.inside, field.type).toBe(true)
    expect(field.below, field.type).toBe(false)
  }

  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(async () => (await layout()).every(field => field.below)).toBe(true)
  for (const field of await layout()) {
    expect(field.overlaps, field.type).toBe(false)
    expect(field.inside, field.type).toBe(true)
  }
})
