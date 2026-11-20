import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// An English source with a title, a block and an item (E2EFixtureController
// :synchronized_translation, source_only), translated from the listing with
// "Create and translate [NO]". A fake model answers
// (E2eProject.FieldActionModel): each text comes back with " (AI)". The texts
// fill the new translation's form as unsaved changes; the save resolves its
// work. The admin is in Norwegian, so the locators read its labels.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/on')).ok()).toBe(true)
})

// AI is application config, which outlives the test's sandbox.
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
})

test('create and translate from the listing fills the form, and the save empties the work list', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/synchronized-translation', {
    data: { source_only: 'true', source_language: 'en' },
  })
  expect(response.ok()).toBeTruthy()
  expect(await response.json()).toHaveProperty('source_id')
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/sync_test/articles')
  await syncLV(page)

  // The source is the listing's one row
  const row = page.locator('.list-row')
  await expect(row).toHaveCount(1)
  await row.getByTestId('circle-dropdown-button').click()
  await row.getByRole('button', { name: /Opprett og oversett \[NO\]/ }).click()

  // The new translation's form, with the run started and the parameter gone
  const panel = page.locator('#translation-panel')
  await expect(panel).toBeVisible({ timeout: 10000 })
  await expect(page).toHaveURL(/\/admin\/sync_test\/articles\/update\/\d+$/)
  await syncLV(page)

  const items = panel.locator('[data-translation-item]')
  await expect(items).toHaveCount(3)
  await expect(panel.locator('[data-translation-item][data-ai="filled"]')).toHaveCount(3, { timeout: 15000 })
  await expect(panel.locator('[data-ai-status="done"]')).toBeVisible()

  // Filled in as unsaved changes: the title, the block's text, the item's label
  await expect(page.locator('input[name="article[title]"]')).toHaveValue('Kilden (AI)')
  await expect(page.locator('.block[data-translation-work]')).toContainText('Første avsnitt (AI)')
  await expect(page.locator('input[name$="[label]"]').first()).toHaveValue('Mer (AI)')
  await panel.screenshot({ path: testInfo.outputPath('translate-with-ai-filled.png') })

  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Lagre og redigér videre' }).click()

  await expect(items).toHaveCount(0, { timeout: 15000 })
  await expect(panel.locator('.translation-done')).toBeVisible()
  await expect(page.locator('input[name="article[title]"]')).toHaveValue('Kilden (AI)')

  expect(errors).toEqual([])
})

// A rich text in a subform's row (the source's quote) is left to the editor
// until the server can give a row's editor a text (#3757): it stays in the
// work list without an AI action, and the run leaves its editor and hidden
// input with the source's text.
test('a rich text in a subform row is not filled and has no AI action', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/synchronized-translation', {
    data: { source_only: 'true', source_language: 'en', rich_quote: 'true' },
  })
  expect(response.ok()).toBeTruthy()
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.goto('/admin/sync_test/articles')
  await syncLV(page)

  const row = page.locator('.list-row')
  await expect(row).toHaveCount(1)
  await row.getByTestId('circle-dropdown-button').click()
  await row.getByRole('button', { name: /Opprett og oversett \[NO\]/ }).click()

  const panel = page.locator('#translation-panel')
  await expect(panel).toBeVisible({ timeout: 10000 })
  await expect(page).toHaveURL(/\/admin\/sync_test\/articles\/update\/\d+$/)
  await syncLV(page)

  await expect(panel.locator('[data-ai-status="done"]')).toBeVisible({ timeout: 15000 })
  await expect(page.locator('input[name="article[title]"]')).toHaveValue('Kilden (AI)')

  const quote = panel.locator('[data-translation-item^="quotes/"]')
  await expect(quote).toHaveCount(1)
  await expect(quote).not.toHaveAttribute('data-ai', /.*/)
  await expect(quote.getByTestId('translation-ai-item')).toHaveCount(0)

  const input = page.locator('input[name="article[quotes][0][text]"]')
  const editor = page.locator('[id$="_quotes_0_text-rich-text"] .ProseMirror')
  await expect(input).toHaveValue('<p>Sitatet</p>')
  await expect(editor).toHaveText('Sitatet')

  expect(errors).toEqual([])
})
