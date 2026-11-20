import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A rich text in a subform's row follows a change the server makes to it
// (#3757): another editor's, after the rows moved, in an embeds_many row
// (an article's quotes, E2eProject.SyncTest.Article) and in a page's
// rich-text variable (a has_many row). The visible editor shows what its
// hidden input holds, and typing there builds on it.

const quoteRows = page => page.locator('[id$="quotes-sortable"] > .subform-entry')
const editorOf = row => row.locator('.ProseMirror')
const inputOf = row => row.locator('input.tiptap-text')

async function openArticle(page, quotes) {
  const response = await page.request.post('/e2e/synchronized-translation', {
    data: { source_only: 'true', source_language: 'en', quotes },
  })
  expect(response.ok()).toBeTruthy()
  const { source_id } = await response.json()
  return `/admin/sync_test/articles/update/${source_id}`
}

async function open(page, path, rows, count) {
  await page.setViewportSize({ width: 1440, height: 2400 })
  await page.goto(path)
  await syncLV(page)
  await expect(rows(page)).toHaveCount(count)
  await expect(editorOf(rows(page).first())).toBeVisible()
}

// textContent: a page variable's editor is in a closed disclosure
const expectTexts = (page, rows, texts) =>
  expect.poll(() => rows(page).locator('.ProseMirror').allTextContents()).toEqual(texts)

const expectInputs = (page, rows, texts) =>
  expect.poll(() => rows(page).locator('input.tiptap-text').evaluateAll(inputs => inputs.map(input => input.value))).toEqual(
    texts.map(text => `<p>${text}</p>`)
  )

// Replaces a row's text and leaves the field, which ships it
async function retype(page, row, text) {
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+a')
  await page.keyboard.type(text)
  await expect(inputOf(row)).toHaveValue(`<p>${text}</p>`)
  await editorOf(row).blur()
  await syncLV(page)
}

// Types at the end of a row's text and leaves the field
async function append(page, row, text) {
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+End')
  await page.keyboard.type(text)
  await editorOf(row).blur()
  await syncLV(page)
}

test('another editor’s change to a row’s rich text shows in the row, and typing there keeps it', async ({ page, secondUserPage }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  secondUserPage.on('pageerror', error => errors.push(error.message))

  const path = await openArticle(page, ['Første', 'Andre'])
  await open(page, path, quoteRows, 2)
  await open(secondUserPage, path, quoteRows, 2)

  await retype(page, quoteRows(page).nth(1), 'Endret')

  await expectInputs(secondUserPage, quoteRows, ['Første', 'Endret'])
  await expectTexts(secondUserPage, quoteRows, ['Første', 'Endret'])

  await append(secondUserPage, quoteRows(secondUserPage).nth(1), ' igjen')
  await expectTexts(secondUserPage, quoteRows, ['Første', 'Endret igjen'])
  await expectTexts(page, quoteRows, ['Første', 'Endret igjen'])
  await expectInputs(page, quoteRows, ['Første', 'Endret igjen'])

  expect(errors).toEqual([])
})

// As `pages/draft-reorder.spec.js`: Sortable's fallback drag starts once the
// pointer has moved (`.sortable-fallback`), and reorders once it has crossed
// the target's swap threshold, which the ghost (`is-sorting`) shows
async function drag(page, rows, from, to) {
  await syncLV(page)
  const handle = rows(page).nth(from).locator('.subform-handle')
  await rows(page).nth(to).scrollIntoViewIfNeeded()
  await handle.scrollIntoViewIfNeeded()
  const source = await handle.boundingBox()
  const target = await rows(page).nth(to).locator('.subform-handle').boundingBox()
  await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2)
  await page.mouse.down()
  await page.mouse.move(source.x + source.width / 2 + 12, source.y + source.height / 2, { steps: 4 })
  await expect(page.locator('.sortable-fallback')).toBeVisible()
  await page.mouse.move(target.x + target.width / 2, target.y + (to < from ? 2 : target.height - 2), { steps: 25 })
  await expect.poll(() => rows(page).evaluateAll(els => els.findIndex(el => el.classList.contains('is-sorting')))).toBe(to)
  await page.mouse.up()
  await syncLV(page)
}

test('a row’s rich text follows another editor’s change after rows were moved, added and removed', async ({ page, secondUserPage }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  secondUserPage.on('pageerror', error => errors.push(error.message))
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)

  const path = await openArticle(page, ['Første', 'Andre', 'Tredje'])
  await open(page, path, quoteRows, 3)
  await open(secondUserPage, path, quoteRows, 3)

  // Editor 1 moves the last row to the top (the move ships with the next
  // field it leaves) …
  await drag(page, quoteRows, 2, 0)
  await expectInputs(page, quoteRows, ['Tredje', 'Første', 'Andre'])
  await expectTexts(page, quoteRows, ['Tredje', 'Første', 'Andre'])

  // … inserts a row above the second and writes in it
  await quoteRows(page).nth(1).hover()
  await quoteRows(page).nth(1).getByRole('button', { name: 'Sett inn rad' }).click()
  await expect(quoteRows(page)).toHaveCount(4)
  await syncLV(page)
  await retype(page, quoteRows(page).nth(1), 'Ny')
  await expectInputs(secondUserPage, quoteRows, ['Tredje', 'Ny', 'Første', 'Andre'])
  await expectTexts(secondUserPage, quoteRows, ['Tredje', 'Ny', 'Første', 'Andre'])

  // … removes the first, and changes the last
  await quoteRows(page).nth(0).hover()
  await quoteRows(page).nth(0).getByRole('button', { name: 'Fjern element' }).click()
  await expect(quoteRows(page)).toHaveCount(3)
  await syncLV(page)
  await retype(page, quoteRows(page).nth(2), 'Andre endret')

  await expectTexts(secondUserPage, quoteRows, ['Ny', 'Første', 'Andre endret'])
  await expectInputs(secondUserPage, quoteRows, ['Ny', 'Første', 'Andre endret'])

  // Editor 2 moves a row itself, and editor 1 changes the moved row
  await drag(secondUserPage, quoteRows, 2, 0)
  await expectTexts(secondUserPage, quoteRows, ['Andre endret', 'Ny', 'Første'])
  await append(secondUserPage, quoteRows(secondUserPage).nth(1), ' rad')
  await expectTexts(page, quoteRows, ['Andre endret', 'Ny rad', 'Første'])
  await retype(page, quoteRows(page).nth(0), 'Flyttet')
  await expectTexts(secondUserPage, quoteRows, ['Flyttet', 'Ny rad', 'Første'])

  // Typing there builds on it, in both tabs
  await append(secondUserPage, quoteRows(secondUserPage).nth(0), ' og skrevet')
  await expectTexts(page, quoteRows, ['Flyttet og skrevet', 'Ny rad', 'Første'])
  await expectInputs(page, quoteRows, ['Flyttet og skrevet', 'Ny rad', 'Første'])
  await expectTexts(secondUserPage, quoteRows, ['Flyttet og skrevet', 'Ny rad', 'Første'])

  expect(errors).toEqual([])
})

// A page's variables are has_many rows, which reach the other editors when
// the page is saved (`take_saved_entry`)
const varRows = page => page.locator('.subform--vars .vars-row')

// `tab`: the Advanced tab's name in the editor's language
async function openVars(page, path, tab) {
  await page.setViewportSize({ width: 1440, height: 2400 })
  await page.goto(path)
  await syncLV(page)
  await page.getByRole('button', { name: tab, exact: true }).click()
  await expect(varRows(page)).toHaveCount(3)
}

async function retypeVar(page, row, text) {
  await row.locator('.variable-header').click()
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+a')
  await page.keyboard.type(text)
  await expect(inputOf(row)).toHaveValue(`<p>${text}</p>`)
  await editorOf(row).blur()
  await syncLV(page)
}

// The other editor's assertions are what tell that the save reached them
async function saveAndStay(page) {
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Lagre og redigér videre' }).click()
  await syncLV(page)
}

test('a rich-text page variable shows another editor’s saved text, after the variables were moved', async ({ page, secondUserPage }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  secondUserPage.on('pageerror', error => errors.push(error.message))
  expect((await page.request.post('/e2e/setup_fixtures/rich-text-vars-page')).ok()).toBe(true)

  await page.goto('/admin/pages')
  await syncLV(page)
  await page.getByRole('link', { name: 'Rich text variables', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages\/update\/\d+$/)
  const path = new URL(page.url()).pathname
  await openVars(page, path, 'Avansert')
  await openVars(secondUserPage, path, 'Advanced')
  await expectTexts(secondUserPage, varRows, ['Første', 'Andre', 'Tredje'])

  await retypeVar(page, varRows(page).nth(1), 'Andre endret')
  await saveAndStay(page)
  await expectInputs(secondUserPage, varRows, ['Første', 'Andre endret', 'Tredje'])
  await expectTexts(secondUserPage, varRows, ['Første', 'Andre endret', 'Tredje'])

  await drag(page, varRows, 2, 0)
  await expectTexts(page, varRows, ['Tredje', 'Første', 'Andre endret'])
  await retypeVar(page, varRows(page).nth(0), 'Flyttet')
  await saveAndStay(page)
  await expectTexts(secondUserPage, varRows, ['Flyttet', 'Første', 'Andre endret'])
  await expectInputs(secondUserPage, varRows, ['Flyttet', 'Første', 'Andre endret'])

  expect(errors).toEqual([])
})

// Resolves when the form next sends a `validate` (the hidden input's
// debounce has run out); registered before the page connects
function watchValidates(page) {
  let waiting = []
  page.on('websocket', ws => ws.on('framesent', frame => {
    if (!String(frame.payload).includes('"event":"validate"')) return
    waiting.forEach(resolve => resolve())
    waiting = []
  }))
  return () => new Promise(resolve => waiting.push(resolve))
}

// Types `words` into `editor` with a pause after each, long enough for the
// debounce to send the text so far; the next word is typed while the
// server's answer to it is on its way
async function typeWithPauses(page, editor, words, nextValidate) {
  await editor.click()
  await page.keyboard.press('ControlOrMeta+End')
  for (const word of words) {
    const sent = nextValidate()
    await page.keyboard.type(word, { delay: 15 })
    await sent
  }
}

const sentence = [' Det', ' var', ' en', ' gang', ' en', ' konge', ' som', ' het', ' Olav.']

test('typing in a row’s rich text while the form validates keeps every keystroke where it was typed', async ({ page }) => {
  const nextValidate = watchValidates(page)
  const path = await openArticle(page, ['Første', 'Andre'])
  await open(page, path, quoteRows, 2)

  await typeWithPauses(page, editorOf(quoteRows(page).nth(1)), sentence, nextValidate)
  const typed = 'Andre' + sentence.join('')
  await expect(editorOf(quoteRows(page).nth(1))).toHaveText(typed)
  await editorOf(quoteRows(page).nth(1)).blur()
  await syncLV(page)
  await expectTexts(page, quoteRows, ['Første', typed])
  await expectInputs(page, quoteRows, ['Første', typed])
})

test('typing in an entry’s own rich text while the form validates keeps every keystroke where it was typed', async ({ page }) => {
  const nextValidate = watchValidates(page)
  await page.goto('/admin/projects/projects')
  await syncLV(page)
  await page.getByRole('link', { name: 'Test Project Gamma' }).click()
  await syncLV(page)

  const editor = page.locator('[id$="_summary-rich-text"] .ProseMirror')
  await expect(editor).toBeVisible()
  const before = await editor.textContent()
  await typeWithPauses(page, editor, sentence, nextValidate)
  await expect(editor).toHaveText(before + sentence.join(''))
  await editor.blur()
  await syncLV(page)
  await expect(editor).toHaveText(before + sentence.join(''))
})

// In turn: field sync ships a relation's rows whole, so two editors typing
// in rows of one relation at the same moment keep only the last to leave
// (as before #3757)
test('two editors typing in different rows in turn keep both texts', async ({ page, secondUserPage }) => {
  const nextA = watchValidates(page)
  const nextB = watchValidates(secondUserPage)
  const path = await openArticle(page, ['Første', 'Andre'])
  await open(page, path, quoteRows, 2)
  await open(secondUserPage, path, quoteRows, 2)

  await typeWithPauses(page, editorOf(quoteRows(page).nth(0)), [' fra', ' en'], nextA)
  await editorOf(quoteRows(page).nth(0)).blur()
  await syncLV(page)
  await expectTexts(secondUserPage, quoteRows, ['Første fra en', 'Andre'])

  await typeWithPauses(secondUserPage, editorOf(quoteRows(secondUserPage).nth(1)), [' fra', ' to'], nextB)
  await editorOf(quoteRows(secondUserPage).nth(1)).blur()
  await syncLV(secondUserPage)

  for (const p of [page, secondUserPage]) {
    await expectTexts(p, quoteRows, ['Første fra en', 'Andre fra to'])
    await expectInputs(p, quoteRows, ['Første fra en', 'Andre fra to'])
  }
})
