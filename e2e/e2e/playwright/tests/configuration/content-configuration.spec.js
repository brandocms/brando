import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function openCreateForm(page, listUrl, heading) {
  await page.goto(listUrl)
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await expect(page.getByRole('heading', { name: heading })).toBeVisible()
}

async function replaceCodeEditor(page, code) {
  await page.locator('.cm-editor').click()
  await page.keyboard.press('ControlOrMeta+A')
  await page.keyboard.type(code)
}

test('creates and persists a module set', async ({ page }) => {
  const listUrl = '/admin/config/content/module_sets'
  await openCreateForm(page, listUrl, 'Create module set')

  await page.getByLabel('Title', { exact: true }).fill('Editorial modules')
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL(listUrl)
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Editorial modules →' })).toBeVisible()
  await expect(page.getByText('0 modules in this set')).toBeVisible()
})

test('creates and persists a container', async ({ page }) => {
  const listUrl = '/admin/config/content/containers'
  await openCreateForm(page, listUrl, 'Create container')

  await page.getByLabel('Name', { exact: true }).fill('Centered content')
  await page.getByLabel('Namespace', { exact: true }).fill('layout')
  await replaceCodeEditor(page, '<section class="centered">{{ content }}</section>')
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL(listUrl)
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Centered content →' })).toBeVisible()
  await expect(page.getByText('layout', { exact: true })).toBeVisible()
})

test('creates and persists a table template', async ({ page }) => {
  const listUrl = '/admin/config/content/table_templates'
  await openCreateForm(page, listUrl, 'Create template')

  await page.getByLabel('Name', { exact: true }).fill('Contact table')
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL(listUrl)
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Contact table →' })).toBeVisible()
})

test('creates and persists a content template', async ({ page }) => {
  const listUrl = '/admin/config/content/templates'
  await openCreateForm(page, listUrl, 'Create template')

  await page.getByLabel('Name', { exact: true }).fill('Landing page')
  await page.getByLabel('Namespace', { exact: true }).fill('pages')
  await page.getByLabel('Instructions').fill('Start with a strong introduction')
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL(listUrl)
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Landing page →' })).toBeVisible()
  await expect(page.getByText('Start with a strong introduction')).toBeVisible()
})

test('creates and persists a palette with a color', async ({ page }) => {
  const listUrl = '/admin/config/content/palettes'
  await openCreateForm(page, listUrl, 'Create palette')

  await page.getByLabel('Published').check()
  await page.getByLabel('Name', { exact: true }).fill('Ocean')
  await page.getByLabel('Key', { exact: true }).fill('ocean')
  await page.getByLabel('Namespace', { exact: true }).fill('brand')
  await page.getByRole('button', { name: 'Add entry' }).click()
  await page.locator('#palette_colors_0_name').fill('Deep blue')
  await page.locator('#palette_colors_0_key').fill('deep-blue')
  await page.locator('#palette_colors_0_hex_value').evaluate((input) => {
    input.value = '#123456'
    input.dispatchEvent(new Event('input', { bubbles: true }))
    input.dispatchEvent(new Event('change', { bubbles: true }))
  })
  await syncLV(page)
  await page.getByTestId('submit').click()

  await expect(page).toHaveURL(listUrl)
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Ocean →' })).toBeVisible()
  await expect(page.getByText('brand', { exact: true })).toBeVisible()
})
