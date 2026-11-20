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
  await page.goto(path)
  await syncLV(page)
  await expect(rows(page)).toHaveCount(count)
  await expect(editorOf(rows(page).first())).toBeVisible()
}

const expectTexts = (page, rows, texts) =>
  expect.poll(() => rows(page).locator('.ProseMirror').allInnerTexts()).toEqual(texts)

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
