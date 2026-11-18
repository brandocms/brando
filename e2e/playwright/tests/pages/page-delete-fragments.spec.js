import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Deleting a page with fragments (#3621): the dialog lists them and asks
// where they go, the page above preselected. A page without fragments keeps
// the plain confirmation. Fragments with no page are listed under the pages.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, creator_id: 1, fields: ['id'], attributes },
  })
  expect(response.ok(), await response.text()).toBe(true)
  return response.json()
}

const page_ = (title, extra = {}) => ({
  title, uri: title.toLowerCase(), language: 'en', status: 'published', template: 'default.html', ...extra,
})

const fragment = (title, key, pageId) => ({
  title, parent_key: 'partials', key, language: 'en', status: 'published', page_id: pageId,
})

const row = (page, title) =>
  page.locator('.list-row').filter({ has: page.locator('.main-content').getByRole('link', { name: title, exact: true }) })

let about, other

test.beforeEach(async ({ page }) => {
  about = await factory(page, 'Brando.Pages.Page', page_('About', { sequence: 1 }))
  const team = await factory(page, 'Brando.Pages.Page', page_('Team', { parent_id: about.id }))
  other = await factory(page, 'Brando.Pages.Page', page_('Other', { sequence: 2 }))
  await factory(page, 'Brando.Pages.Page', page_('Plain', { sequence: 3 }))
  await factory(page, 'Brando.Pages.Fragment', fragment('Team intro', 'team-intro', team.id))
  await factory(page, 'Brando.Pages.Fragment', fragment('Team footer', 'team-footer', team.id))
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages')
  await syncLV(page)
})

async function openDeleteDialog(page, rowLocator, menuItem) {
  await rowLocator.locator('.circle-dropdown-button').first().click()
  await page.getByRole('button', { name: menuItem, exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  return dialog
}

test('a sub page asks where its fragments go, and they move to the page chosen', async ({ page }) => {
  await row(page, 'About').getByTestId('children-button').click()
  const teamRow = row(page, 'About').locator('.child-row').filter({ hasText: 'Team' })

  const dialog = await openDeleteDialog(page, teamRow, 'Delete sub page')
  await expect(dialog.getByRole('heading', { name: 'Delete page?' })).toBeVisible()
  await expect(dialog.locator('.admin-dialog-list li')).toHaveCount(2)
  await expect(dialog.locator('.admin-dialog-list')).toContainText('partials/team-intro')

  // Moving, to the parent, is preselected
  const move = dialog.getByRole('radio', { name: 'Move them to' })
  const select = dialog.getByRole('combobox')
  await expect(move).toBeChecked()
  await expect(select).toHaveValue(String(about.id))

  // Deleting them disables the page select
  await dialog.getByRole('radio', { name: 'Delete them with the page' }).check()
  await expect(select).toBeDisabled()
  await move.check()
  await expect(select).toBeEnabled()

  await select.selectOption(String(other.id))
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click()
  await expect(dialog).toBeHidden()
  await syncLV(page)

  await expect(row(page, 'About').locator('.child-row')).toHaveCount(0)
  await row(page, 'Other').getByTestId('children-button').click()
  const chips = row(page, 'Other').getByRole('group', { name: 'Fragments' })
  await expect(chips.locator('.child-chip-key')).toHaveText(['partials/team-intro', 'partials/team-footer'])
})

test('with no page chosen, the fragments are listed under Fragments without a page', async ({ page }) => {
  await row(page, 'About').getByTestId('children-button').click()
  const teamRow = row(page, 'About').locator('.child-row').filter({ hasText: 'Team' })
  await expect(page.locator('#fragments-without-page')).toHaveCount(0)

  const dialog = await openDeleteDialog(page, teamRow, 'Delete sub page')
  await dialog.getByRole('combobox').selectOption('')
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click()
  await syncLV(page)

  const section = page.locator('#fragments-without-page')
  await expect(section.getByRole('heading', { level: 2 })).toBeVisible()
  await expect(section.locator('.child-chip-key')).toHaveText(['partials/team-footer', 'partials/team-intro'])

  // Each keeps its fragment's menu
  await section.locator('.child-chip').first().locator('.circle-dropdown-button').click()
  await expect(page.getByRole('button', { name: 'Edit fragment' })).toBeVisible()
})

test('deleting them with the page takes them out of the listing', async ({ page }) => {
  await row(page, 'About').getByTestId('children-button').click()
  const teamRow = row(page, 'About').locator('.child-row').filter({ hasText: 'Team' })

  const dialog = await openDeleteDialog(page, teamRow, 'Delete sub page')
  await dialog.getByRole('radio', { name: 'Delete them with the page' }).check()
  await dialog.getByRole('button', { name: 'Delete', exact: true }).click()
  await syncLV(page)

  await expect(row(page, 'About').locator('.child-row')).toHaveCount(0)
  await expect(page.locator('#fragments-without-page')).toHaveCount(0)
})

test('a page without fragments has the plain confirmation', async ({ page }) => {
  const dialog = await openDeleteDialog(page, row(page, 'Plain'), 'Delete')
  await expect(dialog.getByRole('heading', { name: 'Delete page?' })).toBeVisible()
  await expect(dialog.getByRole('radio')).toHaveCount(0)
  await dialog.getByRole('button', { name: 'Cancel' }).click()
  await expect(dialog).toBeHidden()
})
