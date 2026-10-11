import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import { serverLatency } from '../test-support/latency'

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

test('Search fades its backdrop and closes smoothly, including a quick reversal', async ({ page }) => {
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  await page.goto('/admin')
  await syncLV(page)
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await page.evaluate(() => document.body.removeAttribute('data-env'))
  // The nav delegates an open event; use its actual accessible name in this
  // Norwegian view rather than relying on an implementation-only shortcut.
  const trigger = page.locator('#navigation').getByRole('button', { name: /Søk/ })
  await trigger.click()
  const dialog = page.locator('dialog.command-palette')
  const sample = () => dialog.evaluate(el => ({
    panel: Number(getComputedStyle(el).opacity),
    backdrop: Number(getComputedStyle(el, '::backdrop').opacity),
    open: el.open,
  }))
  await expect.poll(async () => (await sample()).backdrop).toBe(1)
  const leaving = await dialog.evaluate(el => new Promise(resolve => {
    el.dispatchEvent(new Event('cancel', { cancelable: true }))
    setTimeout(() => resolve({ panel: Number(getComputedStyle(el).opacity), backdrop: Number(getComputedStyle(el, '::backdrop').opacity), open: el.open }), 90)
  }))
  expect(leaving.open).toBe(true)
  expect(leaving.panel).toBeGreaterThan(0)
  expect(leaving.panel).toBeLessThan(1)
  expect(leaving.backdrop).toBeGreaterThan(0)
  expect(leaving.backdrop).toBeLessThan(1)
  // Reopen before the delayed native close; it must cancel that close.
  await page.evaluate(() => document.querySelector('[phx-hook="Brando.CommandPalette"]').dispatchEvent(new CustomEvent('brando:command-palette:open')))
  await expect(dialog).toHaveAttribute('data-dialog-open', 'true')
  await expect.poll(async () => (await sample()).panel).toBe(1)
  await page.keyboard.press('Escape')
  await expect(dialog).not.toBeVisible()
  await expect(trigger).toBeFocused()
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await trigger.click()
  await page.keyboard.press('Escape')
  await expect(dialog).not.toBeVisible()
})

for (const reduced of [false, true]) {
  test(`Search reserves its loading layout and reveals the reply${reduced ? ' without motion' : ' smoothly'}`, async ({ page }) => {
    const latency = await serverLatency(page)
    await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
    await page.emulateMedia({ reducedMotion: reduced ? 'reduce' : 'no-preference' })
    if (reduced) await page.setViewportSize({ width: 390, height: 844 })
    await page.goto('/admin')
    await syncLV(page)
    await page.evaluate(() => document.body.removeAttribute('data-env'))
    latency.set(900)
    await openWithShortcut(page)
    const body = page.locator('#command-palette-body')
    const skeleton = page.locator('.command-palette-skeleton')
    await expect(body).toHaveAttribute('aria-busy', 'true')
    await expect(results(page)).toHaveAttribute('inert', '')
    await expect(results(page)).toHaveCSS('opacity', '0')
    await expect(skeleton).toHaveCSS('opacity', '1')
    expect((await body.boundingBox()).height).toBeCloseTo(280, 1)
    await body.evaluate(el => {
      window.paletteReveal = null
      const observer = new MutationObserver(() => {
        if (el.getAttribute('aria-busy') !== 'false') return
        observer.disconnect()
        setTimeout(() => {
          window.paletteReveal = {
            results: Number(getComputedStyle(el.querySelector('.command-palette-results')).opacity),
            skeleton: Number(getComputedStyle(el.querySelector('.command-palette-skeleton')).opacity),
            height: el.getBoundingClientRect().height,
            target: el.querySelector('.command-palette-results').getBoundingClientRect().height,
          }
        }, 80)
      })
      observer.observe(el, { attributes: true, attributeFilter: ['aria-busy'] })
    })
    await expect(body).toHaveAttribute('aria-busy', 'false')
    await expect.poll(() => page.evaluate(() => window.paletteReveal)).not.toBeNull()
    const reveal = await page.evaluate(() => window.paletteReveal)
    if (reduced) {
      expect(reveal.results).toBe(1)
      expect(reveal.skeleton).toBe(0)
      expect(reveal.height).toBeCloseTo(reveal.target, 1)
    } else {
      expect(reveal.results).toBeGreaterThan(0)
      expect(reveal.results).toBeLessThan(1)
      expect(reveal.skeleton).toBeGreaterThan(0)
      expect(reveal.skeleton).toBeLessThan(1)
      expect(reveal.height).toBeGreaterThan(Math.min(280, reveal.target))
      expect(reveal.height).toBeLessThan(Math.max(280, reveal.target))
    }
    await expect(results(page)).not.toHaveAttribute('inert', '')
    await expect(results(page)).toHaveCSS('opacity', '1')
    await expect(input(page)).toBeFocused()
  })
}

test('Search accepts typing during loading and a late reply cannot undo closing and reopening', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  const entry = await project(page, { title: 'Palette delayed entry', slug: 'palette-delayed', status: 'draft' })
  await page.goto('/admin')
  await syncLV(page)
  latency.set(900)
  await openWithShortcut(page)
  await input(page).fill('Palette delayed entry')
  await page.keyboard.press('Enter')
  await page.keyboard.press('Escape')
  await expect(palette(page)).toBeHidden()
  latency.set(0)
  await openWithShortcut(page)
  await expect(page.locator('#command-palette-body')).toHaveAttribute('aria-busy', 'false')
  await expect(input(page)).toHaveValue('')
  await expect(page).toHaveURL('/admin')
  await page.keyboard.press('Escape')
  await expect(palette(page)).toBeHidden()

  latency.set(900)
  await openWithShortcut(page)
  await input(page).fill('Palette delayed entry')
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(`/admin/projects/projects/update/${entry.id}`)
})

test('Search opened offline recovers its pending query when the connection returns', async ({ page }) => {
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  await page.goto('/admin')
  await syncLV(page)
  await page.evaluate(() => window.liveSocket.disconnect())
  await openWithShortcut(page)
  await input(page).fill('Test Project Beta')
  await expect(page.locator('#command-palette-body')).toHaveAttribute('aria-busy', 'true')
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
  await expect(results(page)).toHaveAttribute('data-query', 'Test Project Beta')
  await expect(page.locator('#command-palette-body')).toHaveAttribute('aria-busy', 'false')
  await expect(results(page)).not.toHaveAttribute('inert', '')
  await expect(group(page, 'entries').getByRole('option').first()).toContainText('Test Project Beta')
  await page.keyboard.press('Enter')
  await expect(page).toHaveURL(/\/admin\/projects\/projects\/update\/\d+$/)
})

test('a long pasted query cannot leave the opening skeleton stuck', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  await page.goto('/admin')
  await syncLV(page)
  latency.set(800)
  await openWithShortcut(page)
  await input(page).fill('x'.repeat(210))
  await expect(input(page)).toHaveValue('x'.repeat(200))
  await expect(results(page)).toHaveAttribute('data-query', 'x'.repeat(200))
  await expect(page.locator('#command-palette-body')).toHaveAttribute('aria-busy', 'false')
  await expect(results(page)).not.toHaveAttribute('inert', '')
})
