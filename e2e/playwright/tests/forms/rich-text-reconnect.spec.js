import { test, expect } from '../../test-support/setupAuth'
import { syncLV, routeLiveSocket, dropConnection, restoreConnection } from '../../utils'
import { quoteRows, editorOf, inputOf, expectTexts, expectInputs, retype, append } from '../../test-support/richTextRows'

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

// Another editor's changes made while this one was away reach a row's rich
// text through its input once the recovered form is in: the editor shows
// them, and its next change in another row sends them on rather than the
// texts it held.

async function openBoth(page, secondUserPage, quotes) {
  const path = await openArticle(page, quotes)
  for (const p of [page, secondUserPage]) {
    await p.setViewportSize({ width: 1440, height: 2400 })
    await p.goto(path)
    await syncLV(p)
    await expect(quoteRows(p)).toHaveCount(quotes.length)
    await expect(editorOf(quoteRows(p).first())).toBeVisible()
  }
}

test('a row’s rich text another editor changed while this one was away shows the change after the reconnect', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)
  await openBoth(page, secondUserPage, ['Første', 'Andre'])

  await dropConnection(page)
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Endret')
  await restoreConnection(page)

  await expectTexts(page, quoteRows, ['Første', 'Endret'])
  await expectInputs(page, quoteRows, ['Første', 'Endret'])

  // A change in the other row keeps it, in both tabs
  await append(page, quoteRows(page).nth(0), ' mer')
  for (const p of [page, secondUserPage]) {
    await expectTexts(p, quoteRows, ['Første mer', 'Endret'])
    await expectInputs(p, quoteRows, ['Første mer', 'Endret'])
  }
  expect(errors).toEqual([])
})

test('rows below one another editor removed while this one was away each show their own text after the reconnect', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)
  await openBoth(page, secondUserPage, ['Første', 'Andre', 'Tredje'])

  await dropConnection(page)
  // The removal ships with the next field the other editor leaves
  await quoteRows(secondUserPage).nth(0).hover()
  await quoteRows(secondUserPage).nth(0).getByRole('button', { name: 'Remove entry' }).click()
  await expect(quoteRows(secondUserPage)).toHaveCount(2)
  await syncLV(secondUserPage)
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Tredje endret')
  await restoreConnection(page)

  await expect(quoteRows(page)).toHaveCount(2)
  await expectTexts(page, quoteRows, ['Andre', 'Tredje endret'])
  await expectInputs(page, quoteRows, ['Andre', 'Tredje endret'])

  await append(page, quoteRows(page).nth(0), ' mer')
  for (const p of [page, secondUserPage]) {
    await expectTexts(p, quoteRows, ['Andre mer', 'Tredje endret'])
    await expectInputs(p, quoteRows, ['Andre mer', 'Tredje endret'])
  }
  expect(errors).toEqual([])
})

test('a row’s rich text typed in offline while another editor changed it shows what the recovery kept, in the editor and its input', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)
  await openBoth(page, secondUserPage, ['Første', 'Andre'])

  await dropConnection(page)
  const row = quoteRows(page).nth(1)
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+End')
  await page.keyboard.type(' frakoblet')
  await expect(inputOf(row)).toHaveValue('<p>Andre frakoblet</p>')
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Endret')
  await restoreConnection(page)

  // The recovery takes this editor's offline typing (`__offline_edits`)
  // over the other editor's change, which its clock is newer than
  await expectTexts(page, quoteRows, ['Første', 'Andre frakoblet'])
  await expectInputs(page, quoteRows, ['Første', 'Andre frakoblet'])
  expect(errors).toEqual([])
})

// LiveView disconnects a view's hooks for good when it puts the view in its
// permanent error state (a nested view that cannot join), and keeps
// patching them over the connected socket: the hold taken for a rejoin
// ends with the first such patch. The error state is stood in for by
// calling the row's hook as LiveView does then.
test('a row’s rich text disconnected without a rejoin follows the next change the server makes', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await openBoth(page, secondUserPage, ['Første', 'Andre'])

  await quoteRows(page).nth(1).locator('[phx-hook="Brando.TipTap"]').evaluate(el => {
    window.liveSocket.owner(el, view => view.getHook(el).__disconnected())
  })
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Endret')

  await expectTexts(page, quoteRows, ['Første', 'Endret'])
  await expectInputs(page, quoteRows, ['Første', 'Endret'])
  expect(errors).toEqual([])
})
