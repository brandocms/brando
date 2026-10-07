import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('Utilities runs the system check beside the page and links fixes', async ({ page }) => {
  await page.goto('/admin/config/utils')
  await syncLV(page)

  const card = page.locator('#system-check')
  await expect(card.getByRole('heading', { level: 2 })).toBeVisible()
  // The checks load after the page; the card says when they are done.
  await expect(card).toHaveAttribute('aria-busy', 'false', { timeout: 30000 })

  const ids = [
    'versions',
    'migrations',
    'oban',
    'configuration',
    'admin_assets',
    'image_configs',
    'modules',
    'sitemap',
    'robots',
    'json_ld',
    'alt_text',
    'deprecations',
  ]
  for (const id of ids) {
    await expect(card.locator(`li[data-check="${id}"]`)).toHaveCount(1)
  }

  // The server runs from the project, so the source checks run.
  await expect(card.locator('li[data-check="admin_assets"]')).toHaveAttribute('data-status', 'ok')
  await expect(card.locator('li[data-check="deprecations"]')).toHaveAttribute('data-status', 'ok')

  // The E2E app has no sitemap module, and its seeded blocks predate module versions.
  await expect(card.locator('li[data-check="sitemap"]')).toHaveAttribute('data-status', 'warning')
  const modules = card.locator('li[data-check="modules"]')
  await expect(modules).toHaveAttribute('data-status', 'warning')
  await expect(page.getByTestId('system-check-tally')).not.toBeEmpty()

  // Details open in place
  await modules.locator('details summary').click()
  await expect(modules.locator('details li').first()).toBeVisible()

  // Running again shows the skeleton, then the results
  await card.locator('button[phx-click="refresh"]').click()
  await expect(card).toHaveAttribute('aria-busy', 'false', { timeout: 30000 })

  // The fix is a link, not an action
  await modules.locator('a.utils-button').click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules$/)
})
