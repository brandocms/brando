import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// AI that is not a Blueprint's own `ai_actions:` gives suggestions too: the
// Meta drawer's Generate, from the page's site prompts (`trait :meta, ai:` in
// Brando.Pages.Page), and Write with AI in block text, which is on whenever
// AI is configured. A fake model answers (E2eProject.FieldActionModel).
// Nothing reaches a field until the editor accepts it.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/on')).ok()).toBe(true)
})

// AI is application config, which outlives the test's sandbox.
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
})

test('the Meta drawer and block text suggest, and write only what the editor accepts', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  // The meta title's Generate, beside its label
  await page.getByRole('button', { name: 'Meta', exact: true }).click()
  const drawer = page.locator('[id$="-meta-drawer"]')
  const metaTitle = drawer.locator('input[name="page[meta_title]"]')
  const metaTitleField = drawer.locator('.field-wrapper', { has: page.locator('input[name="page[meta_title]"]') })
  const metaSuggestion = metaTitleField.getByTestId('field-ai-suggestion')
  const saved = await metaTitle.inputValue()

  await metaTitleField.getByRole('button', { name: 'Generer', exact: true }).click()
  const suggestedTitle = metaSuggestion.getByRole('textbox', { name: 'Foreslått tekst' })
  await expect(suggestedTitle).toHaveValue(/fjord/)
  // A suggestion, not a value: the field is as it was
  await expect(metaTitle).toHaveValue(saved)

  await suggestedTitle.fill('Velkommen til Brando')
  await metaSuggestion.getByRole('button', { name: 'Godta', exact: true }).click()
  await syncLV(page)
  await expect(metaTitle).toHaveValue('Velkommen til Brando')
  await expect(metaSuggestion.locator('.ai-proposal')).toHaveCount(0)
  await drawer.getByRole('button', { name: 'Lukk', exact: true }).click()

  // Write with AI in the block text's toolbar, with no block_text prompt
  const block = page.locator('[data-tiptap-type="block"][data-tiptap-ai="true"]').first()
  await block.scrollIntoViewIfNeeded()
  await block.locator('.tiptap-target').click()
  await expect(block.locator('.ProseMirror')).toBeVisible()
  const blockText = block.locator('input.tiptap-text')
  const before = await blockText.inputValue()

  await block.getByRole('button', { name: 'Skriv med KI', exact: true }).click()
  await page.getByRole('button', { name: 'Lag forslag', exact: true }).click()
  const suggestion = block.getByRole('region', { name: 'KI-forslag' })
  const suggestedText = suggestion.getByRole('textbox', { name: 'Foreslått tekst' })
  await expect(suggestedText).toHaveValue(/fjord/)
  await expect(blockText).toHaveValue(before)

  // Changed, then accepted: the editor's version goes into the text
  await suggestedText.fill('Et redigert avsnitt om huset.')
  await suggestion.getByRole('button', { name: 'Godta', exact: true }).click()
  await expect(block.locator('.ProseMirror')).toHaveText('Et redigert avsnitt om huset.')
  await expect(blockText).toHaveValue('<p>Et redigert avsnitt om huset.</p>')

  // Saved with the page
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await expect(page.locator('input[name="page[meta_title]"]')).toHaveValue('Velkommen til Brando')
  await expect(page.locator('[data-tiptap-type="block"] input.tiptap-text').first()).toHaveValue('<p>Et redigert avsnitt om huset.</p>')

  expect(errors).toEqual([])
})

test('without AI, block text has no Write with AI and the meta fields no Generate', async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  await expect(page.locator('[data-tiptap-type="block"]').first()).toHaveAttribute('data-tiptap-ai', 'false')
  await expect(page.locator('button[phx-click="run_field_action"]')).toHaveCount(0)
})
