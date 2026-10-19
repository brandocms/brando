import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// A page's subpages open under it as a tree, in the page columns, and its
// fragments as one line of chips after them (`child_listing … style: :chips`
// in Brando.Pages.Page). The chevron in front of the title is the toggle.

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

test.beforeEach(async ({ page }) => {
  const about = await factory(page, 'Brando.Pages.Page', page_('About', { sequence: 1 }))
  for (const [sequence, title, status] of [[0, 'Team', 'published'], [1, 'History', 'published'], [2, 'Careers', 'draft']]) {
    await factory(page, 'Brando.Pages.Page', page_(title, { parent_id: about.id, sequence, status }))
  }
  for (const [title, key] of [['Contact strip', 'contact'], ['Press quotes', 'press']]) {
    await factory(page, 'Brando.Pages.Fragment', { title, parent_key: 'about', key, language: 'en', status: 'published', page_id: about.id })
  }
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages')
  await syncLV(page)
})

const aboutRow = page =>
  page.locator('.list-row').filter({ has: page.locator('.main-content').getByRole('link', { name: 'About', exact: true }) })

test('subpages open as a tree in the page columns, fragments as chips after them', async ({ page }) => {
  const row = aboutRow(page)
  const toggle = row.getByTestId('children-button')
  await expect(row.locator('.children-summary')).toHaveText('3 pages · 2 fragments')

  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-expanded', 'true')

  const children = row.locator('.child-rows .child-row')
  await expect(children).toHaveCount(3)
  await expect(children.locator('.entry-link')).toHaveText(['Team', 'History', 'Careers'])
  await expect(children.nth(2).locator('.status')).toContainText('Draft')

  // The children's status and author sit under the parent's
  const x = locator => locator.evaluate(el => Math.round(el.getBoundingClientRect().x))
  for (const column of ['.listing-alternates', '.status', '.listing-creator', '.circle-dropdown']) {
    const parentCell = row.locator(`.main-content > ${column}`)
    if (await parentCell.count()) {
      expect(await x(children.first().locator(`> ${column}`)), column).toBe(await x(parentCell))
    }
  }
  // and their titles start further in than the parent's
  expect(await x(children.first().locator('.entry-link'))).toBeGreaterThan(await x(row.locator('.main-content .entry-link')))

  // Fragments: a group of chips, each its title and key, after the subpages
  const chips = row.getByRole('group', { name: 'Fragments' })
  await expect(chips.locator('.child-chip:not(.child-chip--add)')).toHaveCount(2)
  await expect(chips.locator('.child-chip-key')).toHaveText(['about/contact', 'about/press'])
  expect(await chips.evaluate(el => el.previousElementSibling.classList.contains('child-rows'))).toBe(true)

  // A chip keeps its fragment's actions in its menu
  await chips.locator('.child-chip').first().locator('.circle-dropdown-button').click()
  await expect(page.getByRole('button', { name: 'Duplicate fragment' })).toBeVisible()
  await expect(page.getByRole('button', { name: 'Delete fragment' })).toBeVisible()
  await page.keyboard.press('Escape')

  // Closing folds the tree again
  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-expanded', 'false')
  await expect(row.locator('.child-row')).toHaveCount(0)
  await expect(row.locator('.child-chips')).toHaveCount(0)
})

test("a fragment chip opens the fragment, and the add chip creates one for the page", async ({ page }) => {
  const row = aboutRow(page)
  await row.locator('.children-summary').click()
  const chips = row.getByRole('group', { name: 'Fragments' })

  await chips.getByRole('link', { name: 'Contact strip' }).click()
  await expect(page).toHaveURL(/\/admin\/pages\/fragments\/update\/\d+$/)

  await page.goBack()
  await syncLV(page)
  await aboutRow(page).getByTestId('children-button').click()
  await aboutRow(page).getByRole('button', { name: 'Create fragment' }).click()
  await expect(page).toHaveURL(/\/admin\/pages\/fragments\/create\?.*page_id=\d+/)
})
