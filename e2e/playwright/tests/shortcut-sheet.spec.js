import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// The keyboard shortcut sheet (`?`, BrandoAdmin.Components.ShortcutSheet) and
// the shortcuts in assets/src/shortcuts. Driven in Norwegian, so the
// locators name the translated labels.

const sheet = page => page.getByRole('dialog', { name: 'Hurtigtaster' })

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 900 })
})

test('? opens the sheet, and escape gives the focus back', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  const search = page.locator('#nav-search')
  await search.focus()
  await page.keyboard.press('?')
  await expect(sheet(page)).toBeVisible()
  await expect(page.locator('#shortcut-sheet-title')).toBeFocused()

  // Grouped, with the "go to" rows this user can follow
  await expect(sheet(page).getByRole('heading', { level: 3 })).toHaveCount(4)
  await expect(sheet(page).locator('[data-shortcut="go-dashboard"] dt')).toHaveText('Gå til Dashbord')
  await expect(sheet(page).locator('[data-shortcut="go-dashboard"] kbd')).toHaveText(['G', 'D'])

  await page.keyboard.press('Escape')
  await expect(sheet(page)).toBeHidden()
  await expect(search).toBeFocused()
})

test('? typed in a text field is text', async ({ page }) => {
  await page.goto('/admin/projects/projects')
  await syncLV(page)

  const filter = page.locator('.filter input[type="text"]').first()
  await filter.click()
  await filter.press('?')
  await expect(filter).toHaveValue('?')
  await expect(sheet(page)).toBeHidden()

  // and so is a sequence
  await filter.fill('')
  await filter.pressSequentially('gd')
  await expect(filter).toHaveValue('gd')
  await expect(page).toHaveURL(/\/admin\/projects\/projects/)
})

test('g then d goes to the dashboard, g then s to search', async ({ page }) => {
  await page.goto('/admin/projects/projects')
  await syncLV(page)

  await page.keyboard.press('g')
  await page.keyboard.press('d')
  await expect(page).toHaveURL(/\/admin$/)
  await syncLV(page)

  await page.keyboard.press('g')
  await page.keyboard.press('s')
  await expect(page).toHaveURL(/\/admin\/search$/)
})

test('c on a listing opens a new entry, f focuses its filter', async ({ page }) => {
  await page.goto('/admin/projects/projects')
  await syncLV(page)

  await page.keyboard.press('f')
  await expect(page.locator('.filter input[type="text"]').first()).toBeFocused()
  await page.locator('.filter input[type="text"]').first().blur()

  await page.keyboard.press('c')
  await expect(page).toHaveURL(/\/admin\/projects\/projects\/create$/)
})

test('the command palette and the user menu open the sheet', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  await page.keyboard.press('ControlOrMeta+k')
  await expect(page.locator('#command-palette-dialog')).toBeVisible()
  await page.locator('#command-palette-input').fill('hurtig')
  await expect(page.locator('#command-palette-results')).toHaveAttribute('data-query', 'hurtig')
  await page.getByRole('option', { name: 'Hurtigtaster' }).click()
  await expect(page.locator('#command-palette-dialog')).toBeHidden()
  await expect(sheet(page)).toBeVisible()
  await sheet(page).getByRole('button', { name: 'Lukk' }).click()
  await expect(sheet(page)).toBeHidden()

  await page.getByTestId('current-user').click()
  await page.getByRole('button', { name: 'Hurtigtaster' }).click()
  await expect(sheet(page)).toBeVisible()
})

test('turned off, single keys do nothing until turned back on', async ({ page }) => {
  await page.goto('/admin/projects/projects')
  await syncLV(page)

  await page.keyboard.press('?')
  await sheet(page).getByRole('checkbox', { name: 'Hurtigtaster med én tast' }).uncheck()
  await page.keyboard.press('Escape')
  await expect(sheet(page)).toBeHidden()

  await page.keyboard.press('g')
  await page.keyboard.press('d')
  await page.keyboard.press('?')
  await expect(sheet(page)).toBeHidden()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)

  // ⌘K is not a single key
  await page.keyboard.press('ControlOrMeta+k')
  await expect(page.locator('#command-palette-dialog')).toBeVisible()
  // `>` lists commands only: the shortcuts row is the first
  await page.locator('#command-palette-input').fill('> hurtig')
  await expect(page.locator('#command-palette-results')).toHaveAttribute('data-query', '> hurtig')
  await page.keyboard.press('Enter')
  await sheet(page).getByRole('checkbox', { name: 'Hurtigtaster med én tast' }).check()
  await page.keyboard.press('Escape')

  await page.keyboard.press('g')
  await page.keyboard.press('d')
  await expect(page).toHaveURL(/\/admin$/)
})

test('g then p opens the live preview in the entry editor, and closes it again', async ({ page }) => {
  test.setTimeout(60000)
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  await page.keyboard.press('g')
  await page.keyboard.press('p')
  await expect(page.locator('.live-preview-wrapper iframe')).toBeVisible({ timeout: 30000 })
  await syncLV(page)

  await page.keyboard.press('g')
  await page.keyboard.press('p')
  await expect(page.locator('.live-preview-wrapper')).toBeHidden()
})
