import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { quoteRows, editorOf, inputOf, expectTexts, expectInputs, retype, append, drag } from '../../test-support/richTextRows'

// A rich text in a subform's row follows a change the server makes to it
// (#3757): another editor's, after the rows moved, in an embeds_many row
// (an article's quotes, E2eProject.SyncTest.Article) and in a page's
// rich-text variable (a has_many row). The visible editor shows what its
// hidden input holds, and typing there builds on it.

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
// server's answer to it is on its way. `midway` runs after the word at its
// index, with the editor still focused.
async function typeWithPauses(page, editor, words, nextValidate, midway = {}) {
  await editor.click()
  await page.keyboard.press('ControlOrMeta+End')
  for (const [index, word] of words.entries()) {
    const sent = nextValidate()
    await page.keyboard.type(word, { delay: 15 })
    await sent
    if (index === midway.after) await midway.run()
  }
}

// `Presence/pendingInputs.js`: how long after a keystroke a patch leaves a
// rich text's input alone
const PENDING_INPUT_MS = 2000

const sentence = [' Det', ' var', ' en', ' gang', ' en', ' konge', ' som', ' het', ' Olav.']

// Halfway, the editor stops typing for longer than the pending-input
// window, and a patch lands then (another editor's change to the title): the
// row's text stays as typed, and typing goes on where it stopped.
test('typing in a row’s rich text while the form validates keeps every keystroke where it was typed', async ({ page, secondUserPage }) => {
  const nextValidate = watchValidates(page)
  const path = await openArticle(page, ['Første', 'Andre'])
  await open(page, path, quoteRows, 2)
  await open(secondUserPage, path, quoteRows, 2)
  const title = p => p.locator('input[name$="[title]"]').first()

  const pauseWhileAPatchLands = async () => {
    // Deliberate: the pause the case is about
    await page.waitForTimeout(PENDING_INPUT_MS + 500)
    await title(secondUserPage).fill('Ny tittel')
    await title(secondUserPage).blur()
    await syncLV(secondUserPage)
    await expect(title(page)).toHaveValue('Ny tittel')
  }

  await typeWithPauses(page, editorOf(quoteRows(page).nth(1)), sentence, nextValidate, { after: 3, run: pauseWhileAPatchLands })
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
