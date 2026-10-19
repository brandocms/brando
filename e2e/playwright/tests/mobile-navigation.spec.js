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

test('a closed drawer cannot be tabbed into, and focus moves into it and back', async ({ page }) => {
  // Configuration holds the current page, so the hook opens its section and
  // shows its rows inline: closed, the drawer must still keep them out of reach.
  await page.goto('/admin/config/content/modules')
  await syncLV(page)

  const toggle = page.getByRole('button', { name: 'Meny', exact: true })
  const drawer = page.locator('#navigation')
  await expect(drawer).toBeHidden()

  await toggle.focus()
  for (let i = 0; i < 6; i++) {
    await page.keyboard.press('Tab')
    expect(await page.evaluate(() => !!document.activeElement.closest('#navigation'))).toBe(false)
  }

  await toggle.click()
  await expect(drawer).toBeVisible()
  // On a link one can see, in the menu: not one in the user row's closed menu
  await expect.poll(() => page.evaluate(() => {
    const el = document.activeElement
    return !!el.closest('#nav') && el.checkVisibility({ visibilityProperty: true })
  })).toBe(true)

  await page.keyboard.press('Escape')
  await expect(drawer).toBeHidden()
  await expect(toggle).toBeFocused()
})

test('Escape closes an open dialog first, and widening the window closes the drawer', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  const toggle = page.getByRole('button', { name: 'Meny', exact: true })
  const drawer = page.locator('#navigation')
  await toggle.click()
  await expect(drawer).toBeVisible()

  // The drawer's own Search row opens the command palette over it
  await drawer.locator('.nav-search-item').click()
  const palette = page.locator('#command-palette-dialog')
  await expect(palette).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(palette).toBeHidden()
  await expect(drawer).toBeVisible()
  await expect(toggle).toHaveAttribute('aria-expanded', 'true')

  await page.setViewportSize({ width: 1440, height: 900 })
  // Hidden on a wide screen, so by id rather than by role
  await expect(page.locator('#mobile-nav-toggle')).toHaveAttribute('aria-expanded', 'false')
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(drawer).toBeHidden()
})

test('the drawer keeps its language row after the sidebar was collapsed on a wide screen', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin')
  await syncLV(page)
  await page.locator('.fullscreen-toggle').click()
  await expect(page.locator('body')).toHaveClass(/sidebar-hidden/)

  await page.setViewportSize({ width: 390, height: 844 })
  await page.getByRole('button', { name: 'Meny', exact: true }).click()
  await expect(page.locator('#navigation')).toBeVisible()
  await expect(page.locator('.content-language-selector')).toBeVisible()
})
