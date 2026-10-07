import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Editors' notes (`Brando.Notes`): threads anchored to the entry, a block, a
// field or selected text, shown in a panel beside the editor. Two editors
// share one sandbox, so the second one sees every change live.
test.describe('Notes', () => {
  test.describe.configure({ mode: 'serial' })
  test.setTimeout(150000)

  const addBlock = async (page, name) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }

  // A page with a Styled Header and a Rich Text Article, saved, open in the editor.
  const createPage = async (page, title, uri) => {
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    await addBlock(page, 'Styled Header')
    const header = page.locator('.header-block textarea').first()
    await header.fill('The pool hall')
    await header.blur()
    await syncLV(page)
    await addBlock(page, 'Rich Text Article')

    await saveAndContinue(page)
    return new URL(page.url()).pathname
  }

  const saveAndContinue = async page => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.form-tool-notes')).toBeVisible()
  }

  const blocks = page => page.locator('.base-block:not(.ref-block)')
  const headerBlock = page => blocks(page).filter({ has: page.locator('.header-block') }).first()
  const articleBlock = page => blocks(page).filter({ hasText: 'Rich Text Article' }).first()
  const panel = page => page.locator('.notes-panel')
  const openNotes = async page => {
    if (!(await panel(page).evaluate(el => el.classList.contains('is-open')))) await page.locator('.form-tool-notes').click()
    await expect(panel(page)).toHaveClass(/is-open/)
  }
  const composer = page => panel(page).locator('.note-composer')
  const thread = (page, text) => panel(page).locator('.note-thread').filter({ hasText: text })

  test('notes on a block, a field and selected text, with replies, mentions and resolving, live for another editor', async ({
    page,
    secondUserPage,
  }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    const path = await createPage(page, 'Notes on a page', 'notes-on-a-page')

    await secondUserPage.setViewportSize({ width: 1440, height: 1000 })
    await secondUserPage.goto(path)
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.header-block textarea').first()).toHaveValue('The pool hall', { timeout: 15000 })

    // A note on a block, from its toolbar
    await headerBlock(page).locator('[data-block-note]').first().click()
    await expect(panel(page)).toHaveClass(/is-open/)
    await expect(composer(page)).toContainText('Styled Header')
    await composer(page).getByRole('textbox').fill('Is the heading final?')
    await composer(page).getByRole('button', { name: 'Add note' }).click()
    await syncLV(page)
    await expect(thread(page, 'Is the heading final?')).toBeVisible()
    await expect(headerBlock(page).locator('[data-block-note]').first()).toHaveAttribute('data-note-count', '1')
    await expect(page.locator('.form-tool-notes')).toContainText('1')

    // The other editor sees it without reloading: the thread and the block's count
    await expect(headerBlock(secondUserPage).locator('[data-block-note]').first()).toHaveAttribute('data-note-count', '1')
    await expect(thread(secondUserPage, 'Is the heading final?')).toHaveCount(1)

    // A note on a field, mentioning the other editor
    await page.getByLabel('Title', { exact: true }).hover()
    await page.locator('.field-note-add').click()
    await expect(composer(page)).toContainText('Title')
    const box = composer(page).getByRole('textbox')
    await box.pressSequentially('@Sec')
    await expect(composer(page).getByRole('option', { name: 'Second Editor' })).toBeVisible()
    await box.press('Enter')
    await box.pressSequentially('can you check the title?')
    await box.press('Enter')
    await syncLV(page)
    const fieldThread = thread(page, 'can you check the title?')
    await expect(fieldThread.locator('.note-mention')).toHaveText('@Second Editor')
    await expect(page.locator('.label-wrapper[data-note-count]')).toHaveCount(1)
    // …who is online, so gets a toast
    await expect(secondUserPage.locator('.toast-stack')).toContainText('mentioned you in a note on Notes on a page')

    // A note on selected text, from "Add note" over the selection
    const article = articleBlock(page)
    const preview = article.locator('[data-tiptap-type="block"] .tiptap-preview-content').first()
    await preview.click()
    const editor = article.locator('.tiptap[contenteditable=true]').first()
    await expect(editor).toBeVisible()
    await editor.evaluate(el => {
      const text = [...el.querySelectorAll('p')].map(p => p.firstChild).find(node => node?.textContent?.includes('content'))
      const start = text.textContent.indexOf('content')
      const range = document.createRange()
      range.setStart(text, start)
      range.setEnd(text, start + 'content'.length)
      const selection = window.getSelection()
      selection.removeAllRanges()
      selection.addRange(range)
    })
    const bubble = article.locator('.tiptap-note-bubble')
    await expect(bubble).toBeVisible()
    await bubble.getByRole('button', { name: /Add note/ }).click()
    await expect(composer(page).locator('.note-quote')).toHaveText('“content”')
    await composer(page).getByRole('textbox').fill('Which content?')
    await composer(page).getByRole('button', { name: 'Add note' }).click()
    await syncLV(page)
    await expect(editor.locator('[data-brando-note]')).toHaveText('content')
    await expect(article.locator('[data-block-note]').first()).toHaveAttribute('data-note-count', '1')
    // The mark is highlighted in the editor
    await expect(editor.locator('[data-brando-note]')).not.toHaveCSS('background-color', 'rgba(0, 0, 0, 0)')

    await expect(panel(page).locator('.notes-tabs button').first()).toContainText('3')

    // The other editor answers in the block's thread; the reply reaches the first
    await openNotes(secondUserPage)
    const theirThread = thread(secondUserPage, 'Is the heading final?')
    await theirThread.getByRole('textbox', { name: 'Reply' }).fill('Yes, final.')
    await theirThread.getByRole('textbox', { name: 'Reply' }).press('Enter')
    await expect(thread(page, 'Is the heading final?')).toContainText('Yes, final.')

    // Resolving moves the thread to the Resolved tab; reopening brings it back
    await thread(page, 'Is the heading final?').getByRole('button', { name: 'Resolve' }).click()
    await syncLV(page)
    const [openTab, resolvedTab] = [panel(page).locator('.notes-tabs button').nth(0), panel(page).locator('.notes-tabs button').nth(1)]
    await expect(openTab).toContainText('2')
    await expect(resolvedTab).toContainText('1')
    await expect(headerBlock(page).locator('[data-block-note]').first()).not.toHaveAttribute('data-note-count')
    await expect(headerBlock(secondUserPage).locator('[data-block-note]').first()).not.toHaveAttribute('data-note-count')
    await resolvedTab.click()
    await expect(thread(page, 'Is the heading final?')).toContainText('Resolved by Brando Admin')
    await thread(page, 'Is the heading final?').getByRole('button', { name: 'Reopen' }).click()
    await syncLV(page)
    await expect(openTab).toContainText('3')
    await expect(resolvedTab).toContainText('0')

    // Clicking a note's place scrolls to its block and marks it
    await openTab.click()
    await page.evaluate(() => window.scrollTo(0, 0))
    await thread(page, 'Which content?').locator('.note-anchor-link').click()
    await expect(article).toHaveClass(/is-note-located/)
    await expect(article).toBeInViewport()

    // A late joiner gets the notes from the server
    await secondUserPage.reload()
    await syncLV(secondUserPage)
    await expect(secondUserPage.locator('.form-tool-notes')).toContainText('3')
  })

  test('notes are kept when a revision is restored, and a deleted block leaves its note detached', async ({ page }) => {
    await page.setViewportSize({ width: 1440, height: 1000 })
    await createPage(page, 'Notes and revisions', 'notes-and-revisions')

    await headerBlock(page).locator('[data-block-note]').first().click()
    await composer(page).getByRole('textbox').fill('Keep this heading')
    await composer(page).getByRole('button', { name: 'Add note' }).click()
    await syncLV(page)
    await expect(thread(page, 'Keep this heading')).toBeVisible()

    // Delete the block and save: the note stays, detached
    const header = headerBlock(page)
    await header.locator('.block-action-dropdown > .block-action').first().click()
    await header.locator('.block-action-dropdown-content button', { hasText: 'Delete' }).first().click()
    await syncLV(page)
    await saveAndContinue(page)
    await openNotes(page)
    await expect(thread(page, 'Keep this heading').locator('.note-state.is-detached')).toBeVisible()
    await expect(thread(page, 'Keep this heading').locator('.note-anchor-link')).not.toHaveAttribute('data-block-uid')

    // Restore the revision that still had the block: the note is attached again
    await page.getByRole('button', { name: 'History', exact: true }).click()
    const drawer = page.locator('[id$="-revisions-drawer"]')
    await expect(drawer).toBeVisible()
    await drawer.getByRole('tab', { name: /Activity/ }).click()
    await expect(drawer.locator('.activity-timeline')).toContainText('Added a note')
    await drawer.getByRole('tab', { name: /Revisions/ }).click()
    const revision = drawer.locator('#revision-line-0')
    await revision.getByTestId('circle-dropdown-button').click()
    await revision.getByRole('button', { name: 'Activate revision' }).click()
    await page.getByRole('button', { name: 'OK' }).click()
    await syncLV(page)
    await drawer.getByRole('button', { name: 'Close' }).click()

    await expect(page.locator('.header-block textarea').first()).toHaveValue('The pool hall', { timeout: 15000 })
    await expect(thread(page, 'Keep this heading')).toHaveCount(1)
    await expect(thread(page, 'Keep this heading').locator('.note-state.is-detached')).toHaveCount(0)
    await expect(headerBlock(page).locator('[data-block-note]').first()).toHaveAttribute('data-note-count', '1')
  })
})
