import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Admin search (Brando.Search, BrandoAdmin.SearchLive): an entry saved with
// block text is indexed, found through the command palette's "See all
// results" row and narrowed with the search page's filters. Driven in
// Norwegian, so the locators carry the translated labels.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const palette = page => page.locator('#command-palette-dialog')
const paletteInput = page => page.locator('#command-palette-input')
const paletteResults = page => page.locator('#command-palette-results')

async function paletteSearch(page, text) {
  await paletteInput(page).fill(text)
  await expect(paletteResults(page)).toHaveAttribute('data-query', text)
}

// The block text, and nothing in the title, slug or introduction says it
const distinctive = 'Kvitsøyfyret'

test('a published entry is found by its block text from the palette and the search page', async ({ page }) => {
  await factory(page, 'Brando.Content.Module', {
    name: { en: 'Lighthouse text', no: 'Fyrtekst' },
    namespace: { en: 'Search', no: 'Søk' },
    help_text: { en: 'A paragraph' },
    class: 'lighthouse',
    type: 'liquid',
    code: '<article>{% ref refs.body %}</article>',
    refs: [
      {
        name: 'body',
        description: 'Text',
        uid: 'search-body',
        data: { type: 'text', data: { text: `<p>${distinctive} lyser over fjorden hver natt.</p>`, extensions: ['p'], type: 'paragraph' } },
      },
    ],
    vars: [],
    multi: false,
    datasource: false,
  })

  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Search owner', slug: 'search-owner', status: 'published', language: 'en',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'The keeper’s house', slug: 'keepers-house', client_id: client.id, introduction: '<p>Intro</p>',
    status: 'draft', language: 'en',
  })

  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 900 })

  // Add the block, publish and save
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await page.getByRole('button', { name: 'Legg til blokk', exact: true }).first().click()
  await page.getByRole('button', { name: /^Søk \d+$/ }).click()
  await page.getByRole('button', { name: 'Fyrtekst', exact: true }).click()
  await syncLV(page)
  await page.getByTestId('status-trigger').click()
  await page.getByTestId('status-options').locator('label', { hasText: 'Publisert' }).click()
  await expect(page.getByTestId('status-options').locator('input[value="published"]')).toBeChecked()
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await syncLV(page)

  // No title says it, so the palette offers the search page, reachable by keyboard
  await page.keyboard.press('ControlOrMeta+k')
  await expect(palette(page)).toBeVisible()
  await paletteSearch(page, distinctive)
  const seeAll = page.getByRole('option', { name: new RegExp(`Se alle treff for «${distinctive}»`) })
  await expect(seeAll).toHaveAttribute('href', `/admin/search?q=${encodeURIComponent(distinctive)}`)
  await expect(seeAll).toHaveAttribute('aria-selected', 'false')
  await page.keyboard.press('ArrowUp')
  await expect(seeAll).toHaveAttribute('aria-selected', 'true')
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(`/admin/search?q=${encodeURIComponent(distinctive)}`)
  await expect(palette(page)).toBeHidden()
  await syncLV(page)

  // The page lists the entry with the text that matched
  const rows = page.locator('#search-list .search-row')
  await expect(rows).toHaveCount(1)
  const row = rows.first()
  await expect(row.getByRole('link')).toHaveAttribute('href', `/admin/projects/projects/update/${project.id}`)
  await expect(row.locator('.search-status')).toHaveAttribute('data-status', 'published')
  await expect(row.locator('.search-snippet mark')).toHaveText(distinctive)

  // Filters narrow it, and live in the URL
  const toolbar = page.getByRole('search')
  await toolbar.getByRole('combobox', { name: 'Status' }).selectOption('draft')
  await expect(page).toHaveURL(/status=draft/)
  await expect(page.locator('#search-none')).toBeVisible()

  await toolbar.getByRole('combobox', { name: 'Status' }).selectOption('published')
  await toolbar.getByRole('combobox', { name: 'Innholdstype' }).selectOption('projects.project')
  await expect(page).toHaveURL(/type=projects\.project/)
  await expect(rows).toHaveCount(1)

  await toolbar.getByRole('combobox', { name: 'Språk' }).selectOption('no')
  await expect(page).toHaveURL(/language=no/)
  await expect(page.locator('#search-none')).toBeVisible()

  await toolbar.getByRole('combobox', { name: 'Språk' }).selectOption('en')
  await expect(rows).toHaveCount(1)
  await row.getByRole('link').click()
  await expect(page).toHaveURL(`/admin/projects/projects/update/${project.id}`)
})

test('the palette opens from a button on a phone', async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/admin')
  await syncLV(page)

  const button = page.getByRole('button', { name: 'Søk', exact: true }).and(page.locator('#mobile-search'))
  await expect(button).toBeVisible()

  await button.click()
  await expect(palette(page)).toBeVisible()
  await expect(paletteInput(page)).toBeFocused()
  const box = await palette(page).boundingBox()
  expect(box.x).toBeGreaterThanOrEqual(0)
  expect(box.x + box.width).toBeLessThanOrEqual(390)

  await paletteSearch(page, 'test')
  await expect(page.locator('#palette-search-all')).toBeVisible()

  await page.keyboard.press('Escape')
  await expect(palette(page)).toBeHidden()
  await expect(button).toBeFocused()

  // Not on a wide screen, where the sidebar has the search row
  await page.setViewportSize({ width: 1440, height: 900 })
  await expect(page.locator('#mobile-search')).toBeHidden()
})
