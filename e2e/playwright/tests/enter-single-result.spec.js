import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Enter on a filter that leaves one result: the link var modal's content
// picker selects it and closes, a listing opens the entry.

async function fixture(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function project(page, title, slug) {
  const client = await fixture(page, 'E2eProject.Projects.Client', { name: `${title} client`, slug: `${slug}-client`, status: 'published', language: 'en' })
  return fixture(page, 'E2eProject.Projects.Project', { title, slug, introduction: '<p>Enter target.</p>', client_id: client.id, status: 'published', language: 'en' })
}

test('Enter in the link picker selects the only match and closes the modal', async ({ page }) => {
  await project(page, 'Enter Target Zephyr', 'enter-target-zephyr')
  await page.goto('/admin/config/navigation/menus/update/1')
  await syncLV(page)

  await page.locator('#menu_items_0_link_0_identifier_id-field-base .link-preview').click()
  const modal = page.locator('#var-menu_items_0_link_0-link-config')
  await modal.getByLabel('Content', { exact: true }).check()
  await modal.getByRole('button', { name: /All content/ }).click()
  await expect(modal.getByRole('button', { name: /All content/ })).toHaveAttribute('aria-pressed', 'true')

  const filter = modal.locator('.identifier-picker-results input')
  const visible = modal.locator('.identifier-options .identifier:visible')

  // Several matches: Enter leaves the modal open and selects nothing
  await filter.fill('e')
  await expect.poll(() => visible.count()).toBeGreaterThan(1)
  await filter.press('Enter')
  await expect(modal).toBeVisible()
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')

  await filter.fill('zephyr')
  await expect(visible).toHaveCount(1)
  await filter.press('Enter')

  await expect(modal).toBeHidden()
  // The menu's form was not submitted
  await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')
  await syncLV(page)

  await page.locator('#menu_items_0_link_0_identifier_id-field-base .link-preview').click()
  await expect(modal.locator('.identifier-picker-details h4')).toHaveText('Enter Target Zephyr')
})

test('Enter in a listing filter opens the only matching entry', async ({ page }) => {
  const target = await project(page, 'Enter Target Zephyr', 'enter-target-zephyr')
  await project(page, 'Enter Pair One', 'enter-pair-one')
  await project(page, 'Enter Pair Two', 'enter-pair-two')

  await page.goto('/admin/projects/projects')
  await syncLV(page)
  const filter = page.locator('#listing-filter-title')

  // Several matches: Enter applies the filter and stays on the listing
  await filter.fill('enter pair')
  await filter.press('Enter')
  await expect(page).toHaveURL(/\/admin\/projects\/projects\?filter:title=enter(\+|%20)pair$/)
  await expect(page.locator('.content-list .list-row')).toHaveCount(2)

  // The row says it is opening (`openingRow.js`) as the navigation starts;
  // LiveView's class commands apply on the next frame
  await page.evaluate(() => {
    window.addEventListener('phx:page-loading-start', ({ detail }) => {
      if (detail.kind !== 'redirect') return
      requestAnimationFrame(() => {
        window.__openingRow = document.querySelector('.list-row.is-opening .entry-link')?.textContent.trim()
      })
    })
  })

  // Enter right after typing, before the filter's debounce has sent it
  await filter.fill('zephyr')
  await filter.press('Enter')
  await expect(page).toHaveURL(`/admin/projects/projects/update/${target.id}`)
  await expect.poll(() => page.evaluate(() => window.__openingRow)).toBe('Enter Target Zephyr')
  await syncLV(page)
  await expect(page.getByTestId('submit')).toBeVisible()
})
