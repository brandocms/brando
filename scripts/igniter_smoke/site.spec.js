import { test, expect } from '@playwright/test'

// The admin's origin. With multi it answers on the endpoint's host only, and
// the site (the base URL) on another; otherwise the two are the same.
const admin = process.env.BRANDO_SMOKE_ADMIN_URL || ''
const multi = process.env.BRANDO_SMOKE_TENANCY_MODE === 'multi'

test('CMS pages render through their own layout and keep unpublished content private', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  let response = await page.goto('/')
  expect(response.status()).toBe(200)
  // The page's own h1 is content — a level-1 header block the editor writes —
  // so a page seeded with only a title has an empty `main`. Assert what the
  // layout and controller actually put on a bare CMS page.
  await expect(page).toHaveTitle('CMS smoke home')
  await expect(page.locator('main#content')).toHaveCount(1)
  await expect(page.locator('html')).toHaveAttribute('lang', 'en')

  await page.goto(`${admin}/admin/login`)
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill('installer@example.test')
  await page.getByLabel('Password', { exact: true }).fill('installer-smoke-test')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/?$/)
  await page.goto(`${admin}/admin/pages`)
  await page.getByText('CMS smoke home', { exact: true }).click()
  await page.getByRole('textbox', { name: 'Title', exact: true }).fill('CMS smoke home updated')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  response = await page.goto('/')
  expect(response.status()).toBe(200)
  await expect(page).toHaveTitle('CMS smoke home updated')

  response = await page.goto('/about')
  expect(response.status()).toBe(200)
  // Only the index action skips the identity prefix.
  await expect(page).toHaveTitle(/CMS smoke about$/)
  // With multi the admin answers on its own host only: on the site's, its
  // paths are the site's 404s.
  for (const path of multi ? ['/draft', '/missing-page', '/admin/login'] : ['/draft', '/missing-page']) {
    response = await page.goto(path)
    expect(response.status()).toBe(404)
    await expect(page.getByText('Unpublished CMS smoke page')).toHaveCount(0)
  }
  // BrandoWeb.SEOController's default text; phx.new's static robots.txt,
  // which Plug.Static would serve first, has no Disallow line. With multi the
  // site's host does not name the admin's path.
  response = await page.goto('/robots.txt')
  expect(response.status()).toBe(200)
  const robots = await response.text()
  expect(robots).toMatch(/^User-agent: \*\nDisallow:/m)
  if (multi) {
    expect(robots).not.toContain('/admin')
  } else {
    expect(robots).toMatch(/^Disallow: \/admin\/$/m)
  }
  if (process.env.BRANDO_SMOKE_BOOTSTRAP === 'precompiled') {
    const health = await page.request.get('/health-check')
    expect(health.status()).toBe(200)
    expect(await health.json()).toEqual({ status: 'preserved' })
  }
  expect(errors).toEqual([])
})
