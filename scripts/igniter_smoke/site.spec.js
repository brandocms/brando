import { test, expect } from '@playwright/test'

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

  await page.goto('/admin/login')
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill('installer@example.test')
  await page.getByLabel('Password', { exact: true }).fill('installer-smoke-test')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/?$/)
  await page.goto('/admin/pages')
  await page.getByText('CMS smoke home', { exact: true }).click()
  await page.getByRole('textbox', { name: 'Title', exact: true }).fill('CMS smoke home updated')
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  response = await page.goto('/')
  expect(response.status()).toBe(200)
  await expect(page).toHaveTitle('CMS smoke home updated')

  response = await page.goto('/about')
  expect(response.status()).toBe(200)
  // Only the index action skips the identity prefix.
  await expect(page).toHaveTitle(/CMS smoke about$/)
  for (const path of ['/draft', '/missing-page']) {
    response = await page.goto(path)
    expect(response.status()).toBe(404)
    await expect(page.getByText('Unpublished CMS smoke page')).toHaveCount(0)
  }
  response = await page.goto('/robots.txt')
  expect(response.status()).toBe(200)
  if (process.env.BRANDO_SMOKE_BOOTSTRAP === 'precompiled') {
    const health = await page.request.get('/health-check')
    expect(health.status()).toBe(200)
    expect(await health.json()).toEqual({ status: 'preserved' })
  }
  expect(errors).toEqual([])
})
