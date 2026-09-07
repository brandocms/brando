import { test, expect } from '@playwright/test'

test('sign in, create and edit generated content, then render it publicly', async ({ page }) => {
  await page.goto('/admin/login')
  await page.getByRole('textbox', { name: 'Email', exact: true }).fill('installer@example.test')
  await page.getByLabel('Password', { exact: true }).fill('installer-smoke-test')
  await page.getByRole('button', { name: 'Log in', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/?$/)

  await page.goto('/admin/catalog/products/create')
  await page.getByRole('textbox', { name: 'Title', exact: true }).fill('Igniter smoke product')
  await page.getByRole('textbox', { name: 'Slug', exact: true }).fill('igniter-smoke-product')
  await page.getByText('Published', { exact: true }).click()
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/catalog\/products$/)
  await page.getByText('Igniter smoke product', { exact: true }).click()
  await page.getByRole('textbox', { name: 'Title', exact: true }).fill('Igniter smoke product updated')
  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/catalog\/products$/)

  const response = await page.goto('/products/1')
  expect(response.status()).toBe(200)
  await expect(page.getByRole('heading', { name: 'Igniter smoke product updated' })).toBeVisible()
})
