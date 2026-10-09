import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// The entry editor's toolbar, split: the tabs on the page, the tools in their
// own group at the right, on one row. Notes is an icon, Languages and Share
// sit in a More menu, and the stuck bar gets a band so content doesn't show
// between the two groups.
const toolbar = page => page.locator('.form-content > .form-tabs')
const tabs = page => toolbar(page).locator('.form-tab-customs')
const tools = page => toolbar(page).locator('.form-tab-builtins')

async function oneRow(page) {
  const a = await tabs(page).boundingBox()
  const b = await tools(page).boundingBox()
  expect(a.y + a.height / 2).toBeCloseTo(b.y + b.height / 2, 0)
  expect(b.x).toBeGreaterThan(a.x + a.width)
  expect((await toolbar(page).boundingBox()).height).toBeLessThan(50)
}

test('tabs and tools share one row, with Notes as an icon and Languages and Share under More', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  for (const width of [1440, 1280]) {
    await page.setViewportSize({ width, height: 900 })
    await expect.poll(async () => (await toolbar(page).boundingBox()).height).toBeLessThan(50)
    await oneRow(page)
    // Every tab is in view, nothing scrolls inside the track
    expect(await tabs(page).evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(0)
    await toolbar(page).screenshot({ path: testInfo.outputPath(`toolbar-${width}.png`) })
  }

  // Notes: an icon with an accessible name, toggling the panel
  const notes = tools(page).locator('.form-tool-notes')
  await expect(notes).toHaveAccessibleName(/^Notes/)
  await expect(notes).toHaveAttribute('data-tooltip', await notes.getAttribute('aria-label'))
  await expect(notes).not.toHaveAttribute('title')
  await notes.click()
  await expect(page.locator('.notes-panel')).toHaveClass(/is-open/)
  await expect(notes).toHaveAttribute('aria-expanded', 'true')
  await notes.click()
  await expect(notes).toHaveAttribute('aria-expanded', 'false')

  // More, by keyboard: Enter opens, Escape closes and gives the focus back
  const more = tools(page).getByRole('button', { name: 'More', exact: true })
  await more.focus()
  await page.keyboard.press('Enter')
  await expect(more).toHaveAttribute('aria-expanded', 'true')
  const menu = page.locator('.form-tool-more-menu')
  await expect(menu.getByRole('button', { name: 'Languages', exact: true })).toBeVisible()
  await expect(menu.getByRole('button', { name: 'Share preview', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  await expect(menu).toBeHidden()
  await expect(more).toHaveAttribute('aria-expanded', 'false')
  await expect(more).toBeFocused()

  // Languages opens the alternates drawer, as its toolbar button did
  await more.click()
  await menu.getByRole('button', { name: 'Languages', exact: true }).click()
  await expect(menu).toBeHidden()
  await expect(page.getByRole('heading', { name: 'Alternates', exact: true })).toBeVisible()
})

test('the stuck toolbar takes a band, and lets it go at the top', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await expect(toolbar(page)).not.toHaveClass(/is-stuck/)
  await page.evaluate(() => window.scrollTo(0, 800))
  await expect(toolbar(page)).toHaveClass(/is-stuck/)
  // The band is opaque behind the gap between the tabs and the tools
  await expect.poll(() => toolbar(page).evaluate(el => getComputedStyle(el, '::before').opacity)).toBe('1')
  await page.evaluate(() => window.scrollTo(0, 0))
  await expect(toolbar(page)).not.toHaveClass(/is-stuck/)
})

test('an entry type without languages or preview has no More menu, and phones keep the toolbar usable', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/prices/price_categories/create')
  await syncLV(page)
  await page.locator('.form-content input[name$="[title]"]').first().fill('Lunch menu')
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
  await syncLV(page)
  await expect(tools(page).getByRole('button', { name: 'Notes', exact: true })).toBeVisible()
  await expect(tools(page).locator('.form-tool-notes .form-tool-count')).toHaveCount(0)
  await expect(tools(page).getByRole('button', { name: 'More', exact: true })).toHaveCount(0)
  await oneRow(page)

  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.setViewportSize({ width: 390, height: 844 })
  await expect.poll(() => page.evaluate(() => document.documentElement.scrollWidth - innerWidth)).toBeLessThanOrEqual(0)
  const save = tools(page).locator('.form-tool-save-button')
  await expect(save).toBeInViewport({ ratio: 1 })
  await expect(tools(page).getByRole('button', { name: 'More', exact: true })).toBeInViewport({ ratio: 1 })
})
