import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Configuration's sidebar submenu lists its screens in groups, each labelled
// by a small heading (#3102). Driven in Norwegian, so the locators name the
// translated labels. Which groups a limited user sees is a LiveView test
// (test/brando_admin/live/nav_groups_test.exs).

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 1200 })
})

test('the groups open and close with Configuration, and their links work', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  const nav = page.locator('#nav')
  const blocks = nav.getByRole('group', { name: 'Byggeklosser' })
  await expect(blocks).toBeHidden()

  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()

  for (const name of ['Nettsted', 'Publisering', 'Byggeklosser', 'Drift']) {
    await expect(nav.getByRole('group', { name })).toBeVisible()
    await expect(nav.getByRole('heading', { name, level: 4 })).toBeVisible()
  }

  await blocks.getByRole('link', { name: 'Blokkmoduler' }).click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await syncLV(page)
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toHaveClass(/active/)

  // Closed, the headings leave with the links
  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()
  await expect(nav.getByRole('heading', { name: 'Byggeklosser', level: 4 })).toBeHidden()
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toBeHidden()
  // and so do the groups, rather than staying as empty named groups
  for (const name of ['Nettsted', 'Publisering', 'Byggeklosser', 'Drift']) {
    await expect(nav.getByRole('group', { name })).toHaveCount(0)
  }

  // Opened again, they are back
  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()
  await expect(nav.getByRole('group', { name: 'Byggeklosser' })).toBeVisible()
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toBeVisible()
})
