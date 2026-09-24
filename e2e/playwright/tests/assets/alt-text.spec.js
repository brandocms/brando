import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Structural locators only: labels are translated and must not be pinned.
test('the image library links to the alt text page, which lists the gap', async ({ page }) => {
  await page.goto('/admin/assets/images')
  await syncLV(page)

  const link = page.getByTestId('alt-text-link')
  await expect(link).toBeVisible()
  await link.click()
  await expect(page).toHaveURL('/admin/assets/images/alt-text')
  await syncLV(page)

  const panel = page.locator('.alt-text-panel')
  await expect(panel.locator('.workspace-panel-heading h2')).toBeVisible()
  await expect(panel.locator('.workspace-panel-heading > span')).toHaveText(/^\d+$/)

  // Without an AI provider nothing can be sent; with one, the estimate
  // stands before the button that sends.
  const describe = panel.locator('button[phx-click="describe"]')
  if (await describe.count()) {
    await expect(panel.locator('.alt-text-estimate p').first()).toBeVisible()
  }

  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth)).toBeLessThanOrEqual(390)
})
