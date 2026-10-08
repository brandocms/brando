import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The listing toolbar's Views menu (`Content.List.SavedViews`): save the
// listing's filters as a view, personal or shared, apply it, go back, open
// the listing with it, delete it. The second half runs as a Norwegian admin,
// so the locators check the translated labels.

const listing = '/admin/projects/projects'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('saved listing views: save, share, apply, back, default and delete', async ({ page }, testInfo) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Fjord', slug: 'fjord', status: 'published', language: 'en',
  })
  await factory(page, 'E2eProject.Projects.Project', {
    title: 'Fjordhuset', slug: 'fjordhuset', client_id: client.id, introduction: '<p>By the fjord.</p>', status: 'published', language: 'en', full_case: true,
  })

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(listing)
  await syncLV(page)

  const rows = page.locator('.content-list .list-row')
  const trigger = page.getByTestId('saved-views-trigger')
  const menu = page.getByTestId('saved-views-menu')
  const all = await rows.count()
  expect(all).toBeGreaterThan(1)

  // A shared view of the full cases
  await page.locator('.boolean-filter .switch').click()
  await expect(page).toHaveURL(/filter:full_case=true/)
  await expect(rows).toHaveCount(1)

  await trigger.click()
  await menu.getByRole('button', { name: 'Save current view…' }).click()
  const dialog = page.getByRole('dialog', { name: 'Save view' })
  await dialog.getByLabel('Name').fill('Full cases')
  await dialog.getByLabel('Share with everyone who can see this list').check()
  await dialog.getByRole('button', { name: 'Save view' }).click()
  await expect(dialog).toBeHidden()
  await expect(page).toHaveURL(/filter:full_case=true&view=\d+$/)
  await expect(trigger).toContainText('Full cases')

  // And a personal one, which nobody else sees
  await trigger.click()
  await menu.getByRole('button', { name: 'Save current view…' }).click()
  await dialog.getByLabel('Name').fill('Only mine')
  await dialog.getByRole('button', { name: 'Save view' }).click()
  await expect(dialog).toBeHidden()

  // Another admin, in Norwegian
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.goto(listing)
  await syncLV(page)
  await expect(rows).toHaveCount(all)

  await page.getByRole('button', { name: 'Lagrede visninger', exact: true }).click()
  const fullCases = menu.getByRole('button', { name: /Full cases/ })
  await expect(fullCases).toContainText('Delt')
  await expect(menu.getByRole('button', { name: /Only mine/ })).toHaveCount(0)
  await menu.screenshot({ path: testInfo.outputPath('saved-views-menu-no-1440.png') })

  // Applying a view is a navigation: back returns to the whole list
  await fullCases.click()
  await expect(page).toHaveURL(/filter:full_case=true&view=\d+$/)
  await expect(rows).toHaveCount(1)
  await page.goBack()
  await expect(page).toHaveURL(new RegExp(`${listing}$`))
  await expect(rows).toHaveCount(all)
  await page.goForward()
  await expect(rows).toHaveCount(1)

  // Opened with it from now on
  await trigger.click()
  await menu.getByRole('button', { name: 'Åpne listen med denne visningen' }).click()
  await syncLV(page)
  // From elsewhere, by the menu's link, which carries the listing's own order
  await page.goto('/admin')
  await syncLV(page)
  await page.locator(`a[href^="${listing}?"]`).first().click()
  await expect(page).toHaveURL(/filter:full_case=true&view=\d+$/)
  await expect(rows).toHaveCount(1)
  await expect(trigger).toContainText('Full cases')

  // At 390 the menu and its trigger fit
  await page.setViewportSize({ width: 390, height: 844 })
  await trigger.scrollIntoViewIfNeeded()
  await trigger.click()
  await expect(menu).toBeVisible()
  const box = await menu.boundingBox()
  expect(box.x).toBeGreaterThanOrEqual(0)
  expect(box.x + box.width).toBeLessThanOrEqual(390)
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
  await page.screenshot({ path: testInfo.outputPath('saved-views-menu-no-390.png') })

  // A superuser may delete the view someone else shares; the list stays filtered
  await menu.getByRole('button', { name: 'Slett «Full cases» …' }).click()
  await page.getByRole('dialog').getByRole('button', { name: 'Slett visning' }).click()
  await expect(page).toHaveURL(/filter:full_case=true$/)
  await expect(rows).toHaveCount(1)
  await expect(trigger).toContainText('Visninger')
})
