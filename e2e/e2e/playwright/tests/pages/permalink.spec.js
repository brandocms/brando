import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function createPage(page) {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Published', { exact: true }).check()
  await page.getByLabel('Title', { exact: true }).fill('About our studio')
  await page.getByLabel('URI', { exact: true }).fill('about-our-studio')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'About our studio →' }).click()
  await syncLV(page)
}

async function changeUrl(page, uri, mode = 'listing') {
  await page.getByLabel('URI', { exact: true }).fill(uri)
  await syncLV(page)
  if (mode === 'self') {
    await page.getByTestId('split-dropdown-button').first().click()
    await page.getByRole('button', { name: 'Save and continue editing' }).click()
  } else if (mode === 'new') {
    await page.getByTestId('split-dropdown-button').first().click()
    await page.getByRole('button', { name: 'Save and create new' }).click()
  } else {
    await page.getByTestId('submit').click()
  }
  const dialog = page.getByRole('dialog', { name: 'URL changed' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByLabel('From', { exact: true })).toHaveValue('/about-our-studio')
  await expect(dialog.getByLabel('To', { exact: true })).toHaveValue(`/${uri}`)
  return dialog
}

test('offers a redirect after saving a page and shows the confirmed rule in SEO', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await createPage(page)
  const dialog = await changeUrl(page, 'our-studio')
  await expect(page.locator('.progress-popup')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('permalink-confirmation.png') })
  await dialog.getByRole('button', { name: 'Create redirect', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  const response = await page.request.get('/about-our-studio', { maxRedirects: 0 })
  expect(response.status()).toBe(301)
  expect(response.headers().location).toBe('/our-studio')
  await page.getByText('Configuration', { exact: true }).click()
  await page.getByRole('link', { name: 'SEO', exact: true }).click()
  await syncLV(page)
  const from = page.locator('input[name="seo[redirects][0][from]"]')
  await expect(from).toHaveValue('/about\\-our\\-studio$')
  await expect(page.locator('input[name="seo[redirects][0][to]"]')).toHaveValue('/our-studio')
  await from.scrollIntoViewIfNeeded()
  await expect(page.locator('.progress-popup')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('permalink-created.png') })
})

test('dismissal continues editing and uses the saved URL for the next change', async ({ page }) => {
  await createPage(page)
  const editUrl = page.url()
  const dialog = await changeUrl(page, 'our-studio', 'self')
  await dialog.getByRole('button', { name: 'Continue without redirect' }).click()
  await expect(dialog).not.toBeVisible()
  await expect(page).toHaveURL(editUrl)
  await expect(page.getByTestId('submit')).toBeEnabled()
  await page.getByLabel('URI', { exact: true }).fill('studio')
  await page.getByTestId('submit').click()
  await expect(dialog).toBeVisible()
  await expect(dialog.getByLabel('From', { exact: true })).toHaveValue('/our-studio')
  await dialog.getByRole('button', { name: 'Continue without redirect' }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
})

test('escape dismisses the prompt and completes Save and create new', async ({ page }) => {
  await createPage(page)
  const dialog = await changeUrl(page, 'our-studio', 'new')
  await page.keyboard.press('Escape')
  await expect(dialog).not.toBeVisible()
  await expect(page).toHaveURL(/\/admin\/pages\/create$/)
})

test('plain forms prompt on slug changes and preserve continue-editing saves', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Categories', exact: true }).click()
  await page.getByRole('link', { name: 'Create new', exact: true }).click()
  await page.getByLabel('Title', { exact: true }).fill('Design')
  await page.getByTestId('submit').click()
  await page.getByRole('link', { name: 'Design →' }).click()
  await syncLV(page)
  const editUrl = page.url()
  const slug = page.getByLabel('Slug', { exact: true })
  await slug.fill('creative-design')
  await page.getByTestId('split-dropdown-button').first().click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  const dialog = page.getByRole('dialog', { name: 'URL changed' })
  await expect(dialog).toBeVisible()
  await expect(dialog.getByLabel('From', { exact: true })).toHaveValue(/\/design$/)
  await expect(dialog.getByLabel('To', { exact: true })).toHaveValue(/\/creative-design$/)
  await dialog.getByRole('button', { name: 'Create redirect', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await expect(page).toHaveURL(editUrl)
  await expect(page.getByTestId('submit')).toBeEnabled()
  await page.getByLabel('Title', { exact: true }).fill('Creative Design')
  await page.getByTestId('submit').click()
  await expect(page).not.toHaveURL(editUrl)
  await expect(dialog).not.toBeVisible()
})
