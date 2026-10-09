import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// AI actions declared on a field (`ai_actions:`: two on the project's title,
// one on its introduction), and Write with AI in its rich text. A fake model
// answers (E2eProject.FieldActionModel), in the language the prompt asks for.
// The reply is a suggestion under the field until it is accepted; discarding
// it leaves the field alone.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/on')).ok()).toBe(true)
})

// AI is application config, which outlives the test's sandbox.
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
})

test('suggests text for a field, in the entry language, and writes it only when accepted', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Fjord', slug: 'fjord', status: 'published', language: 'no' })
  const entry = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Fjordhuset', slug: 'fjordhuset', client_id: client.id, status: 'draft', language: 'no',
    introduction: '<p>Et hus ved <strong>fjorden</strong>.</p>',
  })
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)

  const title = page.locator('input[name="project[title]"]')
  const titleField = page.locator('.field-wrapper', { has: title })
  const titleSuggestion = titleField.getByTestId('field-ai-suggestion')

  // Two actions: a menu beside the label
  await titleField.getByRole('button', { name: 'Skriv med KI' }).click()
  await page.getByRole('button', { name: 'Suggest a title' }).click()
  const suggested = titleSuggestion.getByRole('textbox', { name: 'Foreslått tekst' })
  // The Norwegian entry asked for Norwegian
  await expect(suggested).toHaveValue('Huset ved fjorden')
  await expect(title).toHaveValue('Fjordhuset')
  await page.screenshot({ path: testInfo.outputPath('field-ai-suggestion.png') })

  // Edited, then accepted: it goes into the field, and the suggestion closes
  await suggested.fill('Huset ved fjorden, redigert')
  await titleSuggestion.getByRole('button', { name: 'Godta' }).click()
  await syncLV(page)
  await expect(title).toHaveValue('Huset ved fjorden, redigert')
  await expect(titleSuggestion.locator('.ai-proposal')).toHaveCount(0)

  // One action: a button beside the label
  const introduction = page.locator('[data-footnote-field="introduction"] .tiptap-text')
  const introductionField = page.locator('.field-wrapper', { has: page.locator('[data-footnote-field="introduction"]') })
  const introductionSuggestion = introductionField.getByTestId('field-ai-suggestion')

  await introductionField.getByRole('button', { name: 'Write from the content' }).click()
  await expect(introductionSuggestion.getByRole('textbox')).toHaveValue(/^Et lyst hus ved fjorden/)
  // The bold text would be lost: the suggestion says so
  await expect(introductionSuggestion.getByTestId('field-ai-warning')).toBeVisible()

  // Discarded: the field is as it was
  await introductionSuggestion.getByRole('button', { name: 'Forkast' }).click()
  await expect(introductionSuggestion.locator('.ai-proposal')).toHaveCount(0)
  await expect(introduction).toHaveValue('<p>Et hus ved <strong>fjorden</strong>.</p>')

  // Asked again and accepted: the rich text editor shows it
  await introductionField.getByRole('button', { name: 'Write from the content' }).click()
  await introductionSuggestion.getByRole('button', { name: 'Godta' }).click()
  await syncLV(page)
  await expect(introductionField.locator('.ProseMirror')).toContainText('Et lyst hus ved fjorden')
  await expect(introduction).toHaveValue(/^<p>Et lyst hus ved fjorden/)

  // Saved with the entry
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)
  await expect(title).toHaveValue('Huset ved fjorden, redigert')
  await expect(introduction).toHaveValue(/^<p>Et lyst hus ved fjorden/)

  expect(errors).toEqual([])
})

test('an action with nothing to read says so, and AI off hides the actions and Write with AI', async ({ page }) => {
  await page.goto('/admin/projects/projects/update/1')
  await syncLV(page)

  // Write with AI is in the rich text toolbar whenever AI is configured
  const introductionEditor = page.locator('[data-footnote-field="introduction"]')
  await expect(introductionEditor).toHaveAttribute('data-tiptap-ai', 'true')

  // With the title cleared, shortening it has nothing to read: the action
  // reads the field as the editor sees it, not the saved title the invalid
  // changeset keeps
  const title = page.locator('input[name="project[title]"]')
  const titleField = page.locator('.field-wrapper', { has: title })
  await title.fill('')
  await syncLV(page)
  await titleField.getByRole('button', { name: 'Write with AI' }).click()
  await page.getByRole('button', { name: 'Shorten' }).click()
  await expect(titleField.getByTestId('field-ai-suggestion').getByRole('alert')).toBeVisible()
  await expect(titleField.getByTestId('field-ai-suggestion').getByRole('button', { name: 'Try again' })).toBeVisible()

  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
  await page.reload()
  await syncLV(page)
  await expect(page.locator('button[phx-click="run_field_action"]')).toHaveCount(0)
  await expect(introductionEditor).toHaveAttribute('data-tiptap-ai', 'false')
})
