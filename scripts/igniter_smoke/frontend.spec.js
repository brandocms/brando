import { test, expect } from '@playwright/test'

test('frontend initializes once and the mobile menu can reopen and reverse direction', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 390, height: 844 })
  await page.addInitScript(() => {
    window.frontendEvents = { ready: 0, menu: [] }
    window.addEventListener('APPLICATION:READY', () => { window.frontendEvents.ready += 1 })
    window.addEventListener('APPLICATION:MOBILE_MENU:OPEN', () => window.frontendEvents.menu.push('open'))
    window.addEventListener('APPLICATION:MOBILE_MENU:CLOSED', () => window.frontendEvents.menu.push('closed'))
  })
  await page.goto('/')
  await expect.poll(() => page.evaluate(() => window.frontendEvents.ready)).toBe(1)
  await expect(page.locator('body')).not.toHaveClass(/\bunloaded\b/)

  const hamburger = page.locator('figure.menu-button > .hamburger')
  const background = page.locator('header .mobile-bg')
  const events = () => page.evaluate(() => window.frontendEvents.menu)

  await hamburger.click()
  await expect.poll(events).toEqual(['open'])
  await expect(hamburger).toHaveAttribute('aria-expanded', 'true')
  await expect(background).toBeVisible()
  await expect(background).toHaveCSS('opacity', '1')
  await page.setViewportSize({ width: 390, height: 720 })
  await expect(background).toHaveCSS('height', '720px')

  await hamburger.click()
  await expect.poll(events).toEqual(['open', 'closed'])
  await expect(hamburger).toHaveAttribute('aria-expanded', 'false')
  await expect(background).toBeHidden()

  // Complete animations must not leave stale Motion values on the next open.
  await hamburger.click()
  await expect.poll(events).toEqual(['open', 'closed', 'open'])
  await expect(background).toHaveCSS('opacity', '1')

  // Interrupt a close with an open; the cancelled close must not hide the menu.
  await hamburger.evaluate(el => { el.click(); el.click() })
  await expect.poll(events).toEqual(['open', 'closed', 'open', 'open'])
  await expect(background).toBeVisible()
  await expect(hamburger).toHaveAttribute('aria-expanded', 'true')
  await hamburger.click()
  await expect.poll(events).toEqual(['open', 'closed', 'open', 'open', 'closed'])
  await expect(background).toBeHidden()
  expect(errors).toEqual([])
})
