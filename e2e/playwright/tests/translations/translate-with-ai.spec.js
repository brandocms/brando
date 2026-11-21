import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { quoteRows, expectTexts, expectInputs, retype, append, drag } from '../../test-support/richTextRows'

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

// Rich texts in a subform's rows (the source's quotes) are filled as the
// form's own fields are (#3757): the visible editors show the texts, typing
// there keeps them, and a fill after the rows were moved reaches the moved
// row, in this tab and in a second editor's.
test('rich texts in subform rows are filled, in the moved row and in a second editor', async ({ page, secondUserPage }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  secondUserPage.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 2400 })
  await secondUserPage.setViewportSize({ width: 1440, height: 2400 })

  const response = await page.request.post('/e2e/synchronized-translation', {
    data: { source_only: 'true', source_language: 'en', quotes: ['Sitat en', 'Sitat to'] },
  })
  expect(response.ok()).toBeTruthy()
  // A row keeps its source row's uid, which keys its work item
  const { quote_uids: uids } = await response.json()
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

  // Both quotes are sent and filled, and their editors show the texts
  const quotes = panel.locator('[data-translation-item^="quotes/"]')
  await expect(quotes).toHaveCount(2)
  await expect(panel.locator('[data-translation-item^="quotes/"][data-ai="filled"]')).toHaveCount(2, { timeout: 15000 })
  await expect(panel.locator('[data-ai-status="done"]')).toBeVisible()
  await expectInputs(page, quoteRows, ['Sitat en (AI)', 'Sitat to (AI)'])
  await expectTexts(page, quoteRows, ['Sitat en (AI)', 'Sitat to (AI)'])

  // Typing there builds on the filled text
  await append(page, quoteRows(page).nth(0), ' takk')
  await expectTexts(page, quoteRows, ['Sitat en (AI) takk', 'Sitat to (AI)'])
  await expectInputs(page, quoteRows, ['Sitat en (AI) takk', 'Sitat to (AI)'])

  // A second editor joins and is sent the unsaved rows
  await secondUserPage.goto(new URL(page.url()).pathname)
  await syncLV(secondUserPage)
  await expectTexts(secondUserPage, quoteRows, ['Sitat en (AI) takk', 'Sitat to (AI)'])

  // The second quote moves to the top and is rewritten; its own AI action
  // then fills it again where it now is
  await drag(page, quoteRows, 1, 0)
  await expectTexts(page, quoteRows, ['Sitat to (AI)', 'Sitat en (AI) takk'])
  await retype(page, quoteRows(page).nth(0), 'Utkast')
  await expectTexts(secondUserPage, quoteRows, ['Utkast', 'Sitat en (AI) takk'])

  await panel.locator(`[data-translation-item="quotes/${uids[1]}/text"]`).getByTestId('translation-ai-item').click()
  await expect(panel.locator('[data-ai-status="done"]')).toBeVisible({ timeout: 15000 })

  for (const editor of [page, secondUserPage]) {
    await expectTexts(editor, quoteRows, ['Sitat to (AI)', 'Sitat en (AI) takk'])
    await expectInputs(editor, quoteRows, ['Sitat to (AI)', 'Sitat en (AI) takk'])
  }

  // Typing in the refilled row keeps it, and the second editor sees it
  await append(page, quoteRows(page).nth(0), ' igjen')
  await expectTexts(secondUserPage, quoteRows, ['Sitat to (AI) igjen', 'Sitat en (AI) takk'])

  expect(errors).toEqual([])
})
