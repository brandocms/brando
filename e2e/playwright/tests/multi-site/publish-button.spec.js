// The Publish button under the site switcher, on a static site the
// installation serves itself (`multi-site-static`). Runs only on a server
// started with BRANDO_E2E_MULTI_SITE=1 (playwright.config.js):
//
//   cd e2e && source .envrc
//   BRANDO_E2E_MULTI_SITE=1 scripts/server.sh start
//   cd playwright && BRANDO_E2E_MULTI_SITE=1 BRANDO_E2E_REUSE_SERVER=true \
//     pnpm playwright test tests/multi-site/publish-button.spec.js
import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('publishes the changes from the panel, and says published', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/multi-site-static')).ok()).toBe(true)
  await page.goto('/admin')
  await syncLV(page)

  // Nothing is deployed yet: everything is a change
  const button = page.getByTestId('publish-button')
  await expect(button).toHaveAccessibleName(/Publish changes/)
  await expect(button).toHaveAttribute('aria-expanded', 'false')

  await button.click()
  const panel = page.getByRole('dialog', { name: 'Publish changes' })
  await expect(panel).toBeVisible()
  await expect(button).toHaveAttribute('aria-expanded', 'true')
  await expect(panel.getByRole('heading', { name: 'What will go out' })).toBeVisible()

  // Builds, then deploys; the E2E server runs the jobs as they are queued
  await panel.getByRole('button', { name: 'Publish', exact: true }).click()
  await expect(panel).toBeHidden()
  await expect(button).toHaveAccessibleName(/Published/)

  await button.click()
  const published = page.getByRole('dialog', { name: 'Published' })
  await expect(published.getByRole('link', { name: 'Open Publishing' })).toBeVisible()
  await published.getByRole('link', { name: 'Open Publishing' }).click()
  await expect(page).toHaveURL(/\/admin\/config\/publishing/)
  await syncLV(page)
  // The build it made is the deployed one
  await expect(page.locator('tr[id^="ssg-build-"]')).toHaveCount(1)
  await expect(page.locator('tr[id^="ssg-build-"] .badge-dot')).toHaveCount(1)
})
