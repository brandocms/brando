import { test, expect } from '../../test-support/setupAuth'
import { syncLV, routeLiveSocket, dropConnection, restoreConnection } from '../../utils'

// A Norwegian source with an English translation (E2EFixtureController
// :synchronized_translation). The source added a block and changed the year,
// so the translation has a pending version.

const noOverflow = page =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

test('a translation opens with its pending version, is reviewed and saved', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/synchronized-translation')
  expect(response.ok()).toBeTruthy()
  const { source_id: sourceId, target_id: targetId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)

  const panel = page.locator('#translation-panel')
  await expect(panel).toBeVisible()
  await expect(panel.getByRole('link', { name: 'Open the source' })).toHaveAttribute('href', `/admin/sync_test/articles/update/${sourceId}`)
  await expect(panel.locator('.translation-group').filter({ hasText: 'Needs translation' })).toContainText('Sync text › Body')
  await expect(panel.locator('.translation-group').filter({ hasText: 'Updated from the source' })).toContainText('Year')
  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })

  // The pending year is in the form, and what follows the source is locked.
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2024')
  // A text input is read only and keeps its label; another control is
  // inert, and its label reads out its value and passes no click on.
  const year = page.locator('#article_year-field-wrapper')
  await expect(year).toHaveAttribute('data-source-locked', 'true', { timeout: 5000 })
  await expect(year.locator('input[name="article[year]"]')).toHaveAttribute('readonly', '')
  await expect(year.locator(':scope > .field-base')).not.toHaveAttribute('inert')
  const featured = page.locator('#article_featured-field-wrapper')
  await expect(featured).toHaveAttribute('data-source-locked', 'true')
  await expect(featured.locator(':scope > .field-base')).toHaveAttribute('inert', '')
  await expect(year.locator(':scope > .label-wrapper > label')).toHaveAttribute('for', 'article_year')
  await expect(featured.locator(':scope > .label-wrapper > label')).not.toHaveAttribute('for')
  const featuredValue = featured.locator(':scope > .label-wrapper .field-value')
  await expect(featuredValue).not.toBeEmpty()
  expect(await featuredValue.evaluate(el => getComputedStyle(el).display)).not.toBe('none')
  await expect(page.locator('.blocks-wrapper.is-source-locked .blocks-source-note')).toBeVisible()
  await expect(page.locator('.blocks-wrapper.is-source-locked .block-plus:visible')).toHaveCount(0)
  // Blocks are added, moved and removed only in the source: no drag handles,
  // and no Move up / Move down, Duplicate, Copy or Delete in a block's menu,
  // which goes when nothing else is in it. Read from the styles, without
  // opening a menu: a click in a block would start this editor's focus there.
  const locked = page.locator('.blocks-wrapper.is-source-locked')
  const displays = selector => locked.locator(selector).evaluateAll(els => els.map(el => getComputedStyle(el).display))
  await expect(locked.locator('.sort-handle:visible')).toHaveCount(0)
  await expect(locked.locator('[data-block-move]')).not.toHaveCount(0)
  expect(new Set(await displays('.block-structure-action'))).toEqual(new Set(['none']))
  for (const display of await displays('.block-action-dropdown:not(:has(li:not(.block-structure-action)))')) {
    expect(display).toBe('none')
  }
  await expect(page.locator('.field-wrapper.subform').filter({ has: page.locator('[data-sortable-id="article[items]-sortable"]') }))
    .toHaveAttribute('data-source-structure', 'true')
  // The new block, still in Norwegian, is marked.
  await expect(page.locator('.block[data-translation-work]')).toHaveCount(1)
  await page.screenshot({ path: testInfo.outputPath('translation-editor-desktop.png'), fullPage: true })

  // The new text is kept as it is: mark it reviewed. A reconnect keeps the mark.
  const reviewed = panel.getByLabel('Reviewed')
  await reviewed.check()
  await syncLV(page)
  await page.evaluate(() => window.liveSocket.disconnect())
  await page.waitForTimeout(500)
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
  await expect(panel.getByLabel('Reviewed')).toBeChecked({ timeout: 10000 })

  // Meanwhile the source changes the year again.
  const change = await page.request.post('/e2e/synchronized-translation', { data: { source_id: String(sourceId), year: '2030' } })
  expect(change.ok()).toBeTruthy()

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await panel.scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('translation-editor-mobile.png'), fullPage: false })
  await page.setViewportSize({ width: 1440, height: 1000 })

  // Save and continue: what was reviewed is saved, the newer year is loaded.
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  await expect(page.locator('.translation-notice')).toBeVisible({ timeout: 15000 })
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2030', { timeout: 10000 })
  await expect(panel.locator('.translation-group').filter({ hasText: 'Needs translation' })).toHaveCount(0)

  // The listing shows each language and what is still open.
  await page.goto('/admin/sync_test/articles')
  await syncLV(page)
  const versions = page.locator('.listing-translations').first()
  await expect(versions.locator('.listing-translation.is-source')).toContainText('NO')
  await expect(versions.locator(`a[href="/admin/sync_test/articles/update/${targetId}"]`)).toContainText('Updated from the source')
  await page.screenshot({ path: testInfo.outputPath('translation-listing-desktop.png'), fullPage: true })

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(300)
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('translation-listing-mobile.png'), fullPage: true })

  expect(errors).toEqual([])
})

// The source dropped its block and added another (#3756): the translation's
// form opens with the new block in place of the old one and saves it.
test('a translation saves after the source dropped a block and added another', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  const response = await page.request.post('/e2e/synchronized-translation', { data: { replace_block: 'true' } })
  expect(response.ok()).toBeTruthy()
  const { target_id: targetId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)

  const panel = page.locator('#translation-panel')
  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })
  await expect(panel.locator('.translation-structure')).toBeVisible()
  const blocks = page.locator('.blocks-wrapper .entry-block')
  await expect(blocks).toHaveCount(1)
  await expect(blocks.first()).toContainText('Nytt avsnitt')

  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  // Saved, the translation has the source's blocks: no structural change left.
  await expect(panel.locator('.translation-structure')).toHaveCount(0, { timeout: 15000 })

  await page.reload()
  await syncLV(page)
  await expect(panel).toBeVisible()
  await expect(panel.locator('.translation-structure')).toHaveCount(0)
  await expect(blocks).toHaveCount(1)
  await expect(blocks.first()).toContainText('Nytt avsnitt')

  expect(errors).toEqual([])
})

// One pending version for the form and its blocks (#3760). Two editors: the
// second opens after the source was saved again and gets the version the
// first one's blocks are built on; the first saves, which loads the newer
// version into the shared blocks, and the second's form, with no unsaved
// typing in its fields, loads it in place and saves.
const twoEditors = async (page, secondUserPage) => {
  const response = await page.request.post('/e2e/synchronized-translation')
  expect(response.ok()).toBeTruthy()
  const { source_id: sourceId, target_id: targetId } = await response.json()
  const url = `/admin/sync_test/articles/update/${targetId}`

  await page.goto(url)
  await syncLV(page)
  const panel = page.locator('#translation-panel')
  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })
  const first = await panel.locator('input[name="translation_review[version_id]"]').inputValue()
  await expect(page.locator('.blocks-wrapper .entry-block')).toHaveCount(2)

  // The source is saved again, with another block.
  const change = await page.request.post('/e2e/synchronized-translation', {
    data: { source_id: String(sourceId), year: '2030', add_block: 'Tredje avsnitt' },
  })
  expect(change.ok()).toBeTruthy()

  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  const otherPanel = secondUserPage.locator('#translation-panel')
  await expect(otherPanel.locator('input[name="translation_review[version_id]"]')).toHaveValue(first, { timeout: 10000 })
  await expect(otherPanel.locator('[data-translation-waiting]')).toBeVisible()
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2024')
  await expect(secondUserPage.locator('.blocks-wrapper .entry-block')).toHaveCount(2)

  return { panel, otherPanel, first }
}

const saveAndContinue = async page => {
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
}

test('two editors in a translation load one version, and the one left behind loads it in place', async ({ page, secondUserPage }) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  const { otherPanel, first } = await twoEditors(page, secondUserPage)

  // The first editor saves: the newer version is loaded into the blocks
  await saveAndContinue(page)
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2030', { timeout: 15000 })
  await expect(page.locator('.blocks-wrapper .entry-block')).toHaveCount(3)

  // ... and into the second editor's other fields, without a reload
  await expect(otherPanel.locator('[data-translation-caught-up]')).toBeVisible({ timeout: 10000 })
  await expect(otherPanel.locator('input[name="translation_review[version_id]"]')).not.toHaveValue(first)
  await expect(otherPanel.locator('[data-translation-behind]')).toHaveCount(0)
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2030')
  await expect(secondUserPage.locator('.blocks-wrapper .entry-block')).toHaveCount(3)

  await saveAndContinue(secondUserPage)
  await expect(otherPanel.locator('.translation-structure')).toHaveCount(0, { timeout: 15000 })

  await secondUserPage.reload()
  await syncLV(secondUserPage)
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2030')
  await expect(secondUserPage.locator('.blocks-wrapper .entry-block')).toHaveCount(3)

  expect(errors).toEqual([])
})

// The second editor is typing in the title when the first saves: the form
// stays behind and refuses to save, and the notice's button loads the
// session's version over the typing.
test('an editor left behind with typing in a field loads the newer version with the button', async ({ page, secondUserPage }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  const { otherPanel, first } = await twoEditors(page, secondUserPage)

  const title = secondUserPage.locator('input[name="article[title]"]')
  const saved = await title.inputValue()
  await title.click()
  await title.fill('Typed title')
  await syncLV(secondUserPage)

  await saveAndContinue(page)
  await expect(page.locator('input[name="article[year]"]')).toHaveValue('2030', { timeout: 15000 })

  const behind = otherPanel.locator('[data-translation-behind]')
  await expect(behind).toBeVisible({ timeout: 10000 })
  await expect(secondUserPage.locator('.blocks-wrapper .entry-block')).toHaveCount(3)
  await expect(title).toHaveValue('Typed title')
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2024')

  // A save is refused while behind
  await saveAndContinue(secondUserPage)
  await syncLV(secondUserPage)
  await expect(behind).toBeVisible()
  await expect(otherPanel.locator('input[name="translation_review[version_id]"]')).toHaveValue(first)

  await behind.scrollIntoViewIfNeeded()
  await secondUserPage.screenshot({ path: testInfo.outputPath('translation-behind-desktop.png') })
  await secondUserPage.setViewportSize({ width: 390, height: 844 })
  await behind.scrollIntoViewIfNeeded()
  expect(await noOverflow(secondUserPage)).toBeLessThanOrEqual(0)
  await secondUserPage.screenshot({ path: testInfo.outputPath('translation-behind-mobile.png') })
  await secondUserPage.setViewportSize({ width: 1440, height: 1000 })

  await behind.getByTestId('translation-load-version').click()
  await expect(behind).toHaveCount(0, { timeout: 10000 })
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2030')
  await expect(title).toHaveValue(saved)

  await saveAndContinue(secondUserPage)
  await expect(otherPanel.locator('.translation-structure')).toHaveCount(0, { timeout: 15000 })
  await secondUserPage.reload()
  await syncLV(secondUserPage)
  await expect(secondUserPage.locator('input[name="article[year]"]')).toHaveValue('2030')
  await expect(title).toHaveValue(saved)

  expect(errors).toEqual([])
})

// The connection drops while the editor has typed in a block. The session
// ends with the last editor (no grace period in E2E), so the reconnected
// form loads the version again, over the typing LiveView replays: the save
// keeps the typing and writes the version's blocks.
test('typing in a block survives a lost connection, and the save writes the version', async ({ page }) => {
  test.setTimeout(90000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await routeLiveSocket(page)

  const response = await page.request.post('/e2e/synchronized-translation')
  expect(response.ok()).toBeTruthy()
  const { target_id: targetId } = await response.json()

  await page.goto(`/admin/sync_test/articles/update/${targetId}`)
  await syncLV(page)
  const panel = page.locator('#translation-panel')
  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })
  const blocks = page.locator('.blocks-wrapper .entry-block')
  await expect(blocks).toHaveCount(2)

  const field = blocks.first().locator('[data-tiptap-type="block"]')
  await field.locator('.tiptap-activate').click()
  const editor = field.locator('.tiptap[contenteditable=true]')
  await expect(editor).toBeFocused()
  await editor.press('ControlOrMeta+a')
  await page.keyboard.insertText('Typed paragraph')
  await expect(field.locator('.tiptap-text')).toHaveValue('<p>Typed paragraph</p>')
  await editor.blur()
  await syncLV(page)

  await dropConnection(page)
  await restoreConnection(page)
  await syncLV(page)

  await expect(panel.locator('input[name="translation_review[version_id]"]')).toHaveCount(1, { timeout: 10000 })
  await expect(blocks).toHaveCount(2)
  await expect(blocks.first().locator('.tiptap-text')).toHaveValue('<p>Typed paragraph</p>', { timeout: 10000 })
  await expect(blocks.nth(1)).toContainText('Nytt avsnitt')

  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: 'Save and continue editing' }).click()
  await expect(panel.locator('.translation-structure')).toHaveCount(0, { timeout: 15000 })

  await page.reload()
  await syncLV(page)
  await expect(blocks).toHaveCount(2)
  await expect(blocks.first().locator('.tiptap-text')).toHaveValue('<p>Typed paragraph</p>')
  await expect(blocks.nth(1)).toContainText('Nytt avsnitt')

  expect(errors).toEqual([])
})
