// playwright/tests/my-test.spec.ts
import { test, expect } from '../test-support/setupAuth'

test('should go straight to dashboard if authenticated', async ({ page }) => {
  // Go to the /admin page
  await page.goto('/admin')

  // Wait for navigation and check that the URL is /admin/login
  await expect(page).toHaveURL('/admin')
})
