import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A system check whose fix is a Utilities maintenance row links to that row
// (`#utils-…`). The link only goes there: it is named after the row, and the
// action keeps its own name on the row's button, which is the one that runs it.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('an image config warning links to the Image sizes row by its name', async ({ page }) => {
  // An image processed with settings that have changed since
  await factory(page, 'Brando.Images.Image', {
    path: 'images/default/stale.jpg',
    width: 1200,
    height: 800,
    config_target: 'default',
    status: 'processed',
    config_fingerprint: 'stale',
    formats: ['jpg'],
    sizes: {},
  })

  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/config/utils')
  await syncLV(page)

  const card = page.locator('#system-check')
  await expect(card).toHaveAttribute('aria-busy', 'false', { timeout: 30000 })

  const check = card.locator('li[data-check="image_configs"]')
  await expect(check).toHaveAttribute('data-status', 'warning')
  // Navigation, not the action: the check runs nothing
  await expect(check.getByRole('button')).toHaveCount(0)
  await check.getByRole('link', { name: 'Gå til bildestørrelser' }).click()

  await expect(page).toHaveURL(/#utils-image-sizes$/)
  const row = page.locator('#utils-image-sizes')
  await expect(row).toBeInViewport()
  expect(await row.evaluate(el => el.matches(':target'))).toBe(true)
  await expect(row.getByRole('button', { name: 'Lag endrede bilder på nytt' })).toBeEnabled()
})
