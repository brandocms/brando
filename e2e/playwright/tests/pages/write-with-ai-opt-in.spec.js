import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Write with AI is opt-in: every request is a paid call. A rich text input
// asks for it with `write_with_ai:` (the project's introduction does, its
// summary does not), and a module turns it on for its text blocks with the
// Write with AI switch in the module editor. A fake model answers
// (E2eProject.FieldActionModel).

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/on')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

// AI is application config, and the module cache outlives the sandbox
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/field-ai/off')).ok()).toBe(true)
})

const writeWithAI = { name: 'Skriv med KI', exact: true }

test('a module turns on Write with AI for its text blocks in the module editor', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  // Off in the Index page's text block until its module turns it on
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  const block = page.locator('[data-tiptap-type="block"]').first()
  await block.scrollIntoViewIfNeeded()
  await block.locator('.tiptap-target').click()
  await expect(block.locator('.ProseMirror')).toBeVisible()
  await expect(block).toHaveAttribute('data-tiptap-ai', 'false')
  await expect(block.getByRole('button', writeWithAI)).toHaveCount(0)

  // The switch, off in an existing module, under Overview
  await page.goto('/admin/config/content/modules/update/1')
  await syncLV(page)
  await page.getByRole('tab', { name: 'Oversikt', exact: true }).click()
  const setting = page.locator('[id$="write_with_ai-field-wrapper"]', { hasText: 'Skriv med KI' })
  const toggle = setting.locator('input[type="checkbox"]')
  await expect(toggle).not.toBeChecked()
  await setting.locator('.slider').click()
  await syncLV(page)
  await expect(toggle).toBeChecked()
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/config/content/modules')

  // Saved with the module
  await page.goto('/admin/config/content/modules/update/1')
  await syncLV(page)
  await page.getByRole('tab', { name: 'Oversikt', exact: true }).click()
  await expect(toggle).toBeChecked()

  // The text block offers it, and it answers with a suggestion
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await block.scrollIntoViewIfNeeded()
  await block.locator('.tiptap-target').click()
  await expect(block).toHaveAttribute('data-tiptap-ai', 'true')
  await block.getByRole('button', writeWithAI).click()
  await page.getByRole('button', { name: 'Lag forslag', exact: true }).click()
  await expect(block.getByRole('region', { name: 'KI-forslag' }).getByRole('textbox', { name: 'Foreslått tekst' })).toHaveValue(/fjord/)

  expect(errors).toEqual([])
})

test('rich text offers Write with AI only where the input asks for it', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/projects/projects/update/1')
  await syncLV(page)

  const introduction = page.locator('[data-tiptap-field="introduction"]')
  const summary = page.locator('[data-tiptap-field="summary"]')

  await introduction.locator('.tiptap-target').click()
  await expect(introduction).toHaveAttribute('data-tiptap-ai', 'true')
  await expect(introduction.getByRole('button', writeWithAI)).toBeVisible()

  await summary.scrollIntoViewIfNeeded()
  await summary.locator('.tiptap-target').click()
  await expect(summary.locator('.ProseMirror')).toBeVisible()
  await expect(summary).toHaveAttribute('data-tiptap-ai', 'false')
  await expect(summary.getByRole('button', writeWithAI)).toHaveCount(0)
})
