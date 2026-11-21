import { expect } from '@playwright/test'
import { syncLV } from '../utils'

// Subform rows with a rich text each (rich-text-rows.spec.js,
// translate-with-ai.spec.js): an article's quotes, and their editors

export const quoteRows = page => page.locator('[id$="quotes-sortable"] > .subform-entry')
export const editorOf = row => row.locator('.ProseMirror')
export const inputOf = row => row.locator('input.tiptap-text')

// textContent: a page variable's editor is in a closed disclosure
export const expectTexts = (page, rows, texts) =>
  expect.poll(() => rows(page).locator('.ProseMirror').allTextContents()).toEqual(texts)

export const expectInputs = (page, rows, texts) =>
  expect.poll(() => rows(page).locator('input.tiptap-text').evaluateAll(inputs => inputs.map(input => input.value))).toEqual(
    texts.map(text => `<p>${text}</p>`)
  )

// Replaces a row's text and leaves the field, which ships it
export async function retype(page, row, text) {
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+a')
  await page.keyboard.type(text)
  await expect(inputOf(row)).toHaveValue(`<p>${text}</p>`)
  await editorOf(row).blur()
  await syncLV(page)
}

// Types at the end of a row's text and leaves the field
export async function append(page, row, text) {
  await editorOf(row).click()
  await page.keyboard.press('ControlOrMeta+End')
  await page.keyboard.type(text)
  await editorOf(row).blur()
  await syncLV(page)
}

// As `pages/draft-reorder.spec.js`: Sortable's fallback drag starts once the
// pointer has moved (`.sortable-fallback`), and reorders once it has crossed
// the target's swap threshold, which the ghost (`is-sorting`) shows
export async function drag(page, rows, from, to) {
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
