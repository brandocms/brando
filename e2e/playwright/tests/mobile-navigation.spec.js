import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Below 1024px the sidebar is a drawer, opened by the round menu button
// beside the search one (BrandoAdmin.Nav). Driven in Norwegian, so the
// locators name the translated labels.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 390, height: 844 })
})

test('the menu opens as a drawer on an entry form and closes on Escape, its backdrop and navigation', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  const toggle = page.getByRole('button', { name: 'Meny', exact: true })
  const nav = page.locator('#navigation')
  const dashboard = page.locator('#nav').getByRole('link', { name: 'Dashbord' })

  await expect(toggle).toBeVisible()
  await expect(toggle).toHaveAttribute('aria-expanded', 'false')
  // Closed, it is hidden, not only off screen, so it can't be tabbed into
  await expect(dashboard).toBeHidden()

  await toggle.click()
  await expect(toggle).toHaveAttribute('aria-expanded', 'true')
  await expect(dashboard).toBeVisible()
  await expect(nav).toBeInViewport({ ratio: 1 })

  await page.keyboard.press('Escape')
  await expect(toggle).toHaveAttribute('aria-expanded', 'false')
  await expect(dashboard).toBeHidden()

  // The backdrop, beside the drawer
  await toggle.click()
  await expect(dashboard).toBeVisible()
  await page.mouse.click(370, 600)
  await expect(dashboard).toBeHidden()

  // Following a link closes it on the next page
  await toggle.click()
  await dashboard.click()
  await expect(page).toHaveURL('/admin')
  await syncLV(page)
  await expect(toggle).toHaveAttribute('aria-expanded', 'false')
  await expect(dashboard).toBeHidden()
})

test('a wide screen keeps the sidebar and has no menu button', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin')
  await syncLV(page)

  await expect(page.locator('#mobile-nav-toggle')).toBeHidden()
  await expect(page.locator('#nav').getByRole('link', { name: 'Dashbord' })).toBeVisible()
})
