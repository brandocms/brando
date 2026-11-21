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

// Another editor's text saved while this one was away, with nothing typed
// here: after the reconnect the editor and its input show the saved text,
// and this editor's next save (of another field) keeps it.

// Saves with the keyboard and waits for the write's reply
async function save(page) {
  await page.evaluate(() => {
    window.richTextSaved = false
    window.addEventListener('phx:b:draft-reset', () => { window.richTextSaved = true }, { once: true })
  })
  await page.keyboard.press('ControlOrMeta+s')
  await page.waitForFunction(() => window.richTextSaved)
  await syncLV(page)
}

// The editor, its input, and the two agreeing
async function expectShown(field, text) {
  await expect(editorOf(field)).toHaveText(text)
  await expect(inputOf(field)).toHaveValue(`<p>${text}</p>`)
}

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function changePlainField(page, input, text) {
  await input.fill(text)
  await input.blur()
  await syncLV(page)
}

test('an entry’s own rich text another editor saved while this one was away shows and keeps the saved text', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)

  const summary = p => p.locator('[id$="_summary-rich-text"]')
  const title = p => p.locator('input[name$="[title]"]').first()
  // A project that saves: a client and an introduction, and the summary
  // already saved
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Havglimt', slug: 'havglimt', status: 'published', language: 'en' })
  const entry = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Havglimt retreat', slug: 'havglimt-retreat', client_id: client.id, status: 'published', language: 'en',
    introduction: '<p>Rooms by the sea.</p>', summary: '<p>Gammel</p>',
  })
  const path = `/admin/projects/projects/update/${entry.id}`
  for (const p of [page, secondUserPage]) {
    await p.goto(path)
    await syncLV(p)
    await expectShown(summary(p), 'Gammel')
  }

  await dropConnection(page)
  await retype(secondUserPage, summary(secondUserPage), 'Ny')
  await save(secondUserPage)
  await restoreConnection(page)

  await expectShown(summary(page), 'Ny')

  await changePlainField(page, title(page), 'Havglimt retreat endret')
  await save(page)
  await page.goto(path)
  await syncLV(page)
  await expect(title(page)).toHaveValue('Havglimt retreat endret')
  await expectShown(summary(page), 'Ny')
  expect(errors).toEqual([])
})

test('a row’s rich text another editor saved while this one was away shows and keeps the saved text', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)
  await openBoth(page, secondUserPage, ['Første', 'Gammel'])
  const path = new URL(page.url()).pathname
  const subtitle = p => p.locator('textarea[name$="[subtitle]"]').first()

  await dropConnection(page)
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Ny')
  await save(secondUserPage)
  await restoreConnection(page)

  await expectTexts(page, quoteRows, ['Første', 'Ny'])
  await expectInputs(page, quoteRows, ['Første', 'Ny'])

  await changePlainField(page, subtitle(page), 'Undertittel')
  await save(page)
  await page.goto(path)
  await syncLV(page)
  await expect(subtitle(page)).toHaveValue('Undertittel')
  await expectTexts(page, quoteRows, ['Første', 'Ny'])
  await expectInputs(page, quoteRows, ['Første', 'Ny'])

  // Typed into, the text builds on the saved one
  await dropConnection(page)
  await retype(secondUserPage, quoteRows(secondUserPage).nth(1), 'Nyere')
  await save(secondUserPage)
  await restoreConnection(page)
  await expectTexts(page, quoteRows, ['Første', 'Nyere'])
  await append(page, quoteRows(page).nth(1), ' mer')
  await save(page)
  await page.goto(path)
  await syncLV(page)
  await expectInputs(page, quoteRows, ['Første', 'Nyere mer'])
  expect(errors).toEqual([])
})

test('a rich-text page variable another editor saved while this one was away shows and keeps the saved text', async ({ page, secondUserPage }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)
  expect((await page.request.post('/e2e/setup_fixtures/rich-text-vars-page')).ok()).toBe(true)

  const varRows = p => p.locator('.subform--vars .vars-row')
  const title = p => p.locator('input[name$="[title]"]').first()
  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: 'Rich text variables', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages\/update\/\d+$/)
  const path = new URL(page.url()).pathname
  const openVars = async (p, tab) => {
    await p.setViewportSize({ width: 1440, height: 2400 })
    await p.goto(path)
    await syncLV(p)
    await p.getByRole('button', { name: tab, exact: true }).click()
    await expect(varRows(p)).toHaveCount(3)
  }
  await openVars(page, 'Avansert')
  await openVars(secondUserPage, 'Advanced')

  await dropConnection(page)
  const row = varRows(secondUserPage).nth(1)
  await row.locator('.variable-header').click()
  await retype(secondUserPage, row, 'Andre endret')
  await save(secondUserPage)
  await restoreConnection(page)

  await expectTexts(page, varRows, ['Første', 'Andre endret', 'Tredje'])
  await expectInputs(page, varRows, ['Første', 'Andre endret', 'Tredje'])

  await page.getByRole('button', { name: 'Innhold', exact: true }).click()
  await changePlainField(page, title(page), 'Rich text variables endret')
  await save(page)
  await openVars(page, 'Avansert')
  await expect(title(page)).toHaveValue('Rich text variables endret')
  await expectTexts(page, varRows, ['Første', 'Andre endret', 'Tredje'])
  await expectInputs(page, varRows, ['Første', 'Andre endret', 'Tredje'])
  expect(errors).toEqual([])
})
