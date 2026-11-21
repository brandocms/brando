import { test, expect } from '../../test-support/setupAuth'
import { syncLV, routeLiveSocket, dropConnection, restoreConnection } from '../../utils'
import { quoteRows } from '../../test-support/richTextRows'

// An entry's rich text with unsaved typing comes back from a lost connection
// as it was: LiveView's rejoin renders the saved text and then the recovered
// form, and the editor is left alone through both. The cursor stays where
// typing stopped, and undo still undoes the typing.

// `Presence/pendingInputs.js`: how long after a keystroke a patch leaves a
// rich text's input alone
const PENDING_INPUT_MS = 2000

async function openArticle(page, quotes) {
  const response = await page.request.post('/e2e/synchronized-translation', {
    data: { source_only: 'true', source_language: 'en', quotes },
  })
  expect(response.ok()).toBeTruthy()
  const { source_id } = await response.json()
  return `/admin/sync_test/articles/update/${source_id}`
}

// Resolves when the form next sends a `validate`
function watchValidates(page) {
  let waiting = []
  page.on('websocket', ws => ws.on('framesent', frame => {
    if (!String(frame.payload).includes('"event":"validate"')) return
    waiting.forEach(resolve => resolve())
    waiting = []
  }))
  return () => new Promise(resolve => waiting.push(resolve))
}

// `field`: the rich text's hook element (its editor and hidden input)
async function typeLoseConnectionAndResume(page, field, typed, nextValidate) {
  const editor = field.locator('.ProseMirror')
  const before = await editor.textContent()
  await editor.click()
  await page.keyboard.press('ControlOrMeta+End')
  const sent = nextValidate()
  await page.keyboard.type(typed, { delay: 15 })
  await sent
  // Deliberate: idle past the window in which a patch keeps the input as typed
  await page.waitForTimeout(PENDING_INPUT_MS + 500)

  await dropConnection(page)
  await restoreConnection(page)

  await expect(editor).toHaveText(before + typed)
  await expect(field.locator('input.tiptap-text')).toHaveValue(`<p>${before + typed}</p>`)
  // The rejoin may take the focus; focusing the editor again puts the
  // cursor back where the editor's selection is
  await editor.focus()
  await page.keyboard.type('X')
  await expect(editor).toHaveText(before + typed + 'X')
  await page.keyboard.press('ControlOrMeta+z')
  await expect(editor).toHaveText(before + typed)
  await page.keyboard.press('ControlOrMeta+z')
  await expect(editor).toHaveText(before)
}

test('a row’s rich text with unsaved typing comes back from a lost connection with its cursor and undo', async ({ page }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  const nextValidate = watchValidates(page)
  await routeLiveSocket(page)

  const path = await openArticle(page, ['Første', 'Andre'])
  await page.setViewportSize({ width: 1440, height: 2400 })
  await page.goto(path)
  await syncLV(page)
  await expect(quoteRows(page)).toHaveCount(2)

  await typeLoseConnectionAndResume(page, quoteRows(page).nth(1).locator('[phx-hook="Brando.TipTap"]'), ' og mer', nextValidate)
  expect(errors).toEqual([])
})

test('an entry’s own rich text with unsaved typing comes back from a lost connection with its cursor and undo', async ({ page }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  const nextValidate = watchValidates(page)
  await routeLiveSocket(page)

  await page.goto('/admin/projects/projects')
  await syncLV(page)
  await page.getByRole('link', { name: 'Test Project Gamma' }).click()
  await syncLV(page)

  const field = page.locator('[id$="_summary-rich-text"]')
  await expect(field.locator('.ProseMirror')).toBeVisible()
  // The summary starts empty
  await typeLoseConnectionAndResume(page, field, 'Og mer', nextValidate)
  expect(errors).toEqual([])
})
