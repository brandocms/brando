import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// The command palette (⌘K, Ctrl+K elsewhere): BrandoAdmin.CommandPaletteLive
// and the Brando.CommandPalette hook. Driven by roles and ids, not copy.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function project(page, attributes) {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: "Palette owner", slug: `owner-${attributes.slug}`, status: 'published', language: 'en',
  })
  return factory(page, 'E2eProject.Projects.Project', {
    client_id: client.id, introduction: '<p>Intro</p>', language: 'en', ...attributes,
  })
}

const palette = page => page.locator('#command-palette-dialog')
const input = page => page.locator('#command-palette-input')
const results = page => page.locator('#command-palette-results')
const group = (page, key) => page.locator(`#command-palette-group-${key}`)

async function openWithShortcut(page) {
  await page.keyboard.press('ControlOrMeta+k')
  await expect(palette(page)).toBeVisible()
  await expect(input(page)).toBeFocused()
}

// Typed text is sent after a short debounce; wait for the rows for it
async function search(page, text) {
  await input(page).fill(text)
  await expect(results(page)).toHaveAttribute('data-query', text)
}

test.beforeEach(async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
})

test('opens with the shortcut inside the entry editor and gives focus back on escape', async ({ page }) => {
  const entry = await project(page, { title: 'Palette focus', slug: 'palette-focus', status: 'published' })
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)

  // Typing in a field is left alone until the keys are pressed
  const title = page.locator('input[name$="[title]"]').first()
  await title.click()
  await title.press('End')
  await title.pressSequentially(' k')
  await expect(title).toHaveValue('Palette focus k')
  await expect(palette(page)).toBeHidden()

  await openWithShortcut(page)
  await expect(page.getByRole('dialog')).toBeVisible()

  await page.keyboard.press('Escape')
  await expect(palette(page)).toBeHidden()
  await expect(title).toBeFocused()
})

test('opens from the sidebar, finds an entry by title and opens it with enter', async ({ page }) => {
  await project(page, { title: 'Sommerro rooftop', slug: 'sommerro-rooftop', status: 'draft' })
  const exact = await project(page, { title: 'Sommerro', slug: 'sommerro', status: 'published' })

  await page.goto('/admin')
  await syncLV(page)
  // A row of the sidebar's first section, right after Dashboard, never current
  const button = page.locator('#nav-sections .navigation-section').first().locator('dl').nth(1).locator('#nav-search')
  await expect(button).toBeVisible()
  await expect(button).toHaveAttribute('aria-haspopup', 'dialog')
  await expect(page.locator('#nav-sections .navigation-section').first().locator('dl').first().locator('a')).toHaveAttribute('href', '/admin')
  await button.click()
  await expect(palette(page)).toBeVisible()
  await expect(input(page)).toBeFocused()

  await search(page, 'sommerro')
  // The entries, then the row that opens the search page
  const entries = group(page, 'entries').locator('[role=option].is-entry')
  await expect(entries).toHaveCount(2)
  await expect(group(page, 'entries').getByRole('option').last()).toHaveAttribute('href', '/admin/search?q=sommerro')
  // An exact title before one that starts with the query
  await expect(entries.nth(0)).toHaveAttribute('href', `/admin/projects/projects/update/${exact.id}`)
  await expect(entries.nth(0)).toHaveAttribute('aria-selected', 'true')
  await expect(input(page)).toHaveAttribute('aria-activedescendant', await entries.nth(0).getAttribute('id'))

  await page.keyboard.press('ArrowDown')
  await expect(entries.nth(1)).toHaveAttribute('aria-selected', 'true')
  await expect(entries.nth(0)).toHaveAttribute('aria-selected', 'false')
  await page.keyboard.press('ArrowUp')
  await expect(entries.nth(0)).toHaveAttribute('aria-selected', 'true')

  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(`/admin/projects/projects/update/${exact.id}`)
  await expect(palette(page)).toBeHidden()

  // Closing with the sidebar's button returns focus to it
  await syncLV(page)
  await button.click()
  await expect(palette(page)).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(button).toBeFocused()
  await expect(button).not.toHaveClass(/active/)
})

test('the empty palette shows the places visited last', async ({ page }) => {
  await page.goto('/admin/config/seo')
  await syncLV(page)
  await page.goto('/admin/projects/projects')
  await syncLV(page)
  await page.goto('/admin')
  await syncLV(page)

  await openWithShortcut(page)
  const recent = group(page, 'recent').getByRole('option')
  // Most recent first; the page we're on is left out
  await expect(recent.nth(0)).toHaveAttribute('href', /^\/admin\/projects\/projects/)
  await expect(recent.nth(1)).toHaveAttribute('href', '/admin/config/seo')
  await expect(group(page, 'recent').locator('a[href="/admin"]')).toHaveCount(0)
  await expect(group(page, 'actions')).toBeVisible()

  // Clicking a row opens it and closes the palette
  await recent.nth(1).click()
  await expect(page).toHaveURL('/admin/config/seo')
  await expect(palette(page)).toBeHidden()
})

test('fits a phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/admin')
  await syncLV(page)
  await openWithShortcut(page)
  await search(page, 'test')
  await expect(group(page, 'entries')).toBeVisible()
  const box = await palette(page).boundingBox()
  expect(box.x).toBeGreaterThanOrEqual(0)
  expect(box.x + box.width).toBeLessThanOrEqual(390)
})
