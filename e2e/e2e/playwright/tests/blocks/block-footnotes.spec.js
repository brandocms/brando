import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../../utils'

const fixture = async (page, schema, attributes) => {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const appendModule = async (page, name) => {
  await page.locator('.blocks-wrapper:not(.footnote-storage) > .blocks-content > .block-plus-wrapper button.block-plus').click()
  await page.getByRole('button', { name, exact: true }).click()
  await syncLV(page)
}

const placeCaretAtEnd = async editor => {
  const text = await editor.innerText()
  await editor.click()
  // Bare End scrolls on macOS; it did not move the caret in the old example.
  await editor.press('ControlOrMeta+a')
  await editor.press('ArrowRight')
  await expect.poll(() => editor.evaluate(element => {
    const selection = window.getSelection()
    if (!selection?.rangeCount || !selection.isCollapsed || !element.contains(selection.anchorNode)) return null
    const beforeCaret = document.createRange()
    beforeCaret.selectNodeContents(element)
    beforeCaret.setEnd(selection.anchorNode, selection.anchorOffset)
    return beforeCaret.toString()
  })).toBe(text)
  return text
}

test('notes are opt-in, keep their subtree on save, and renumber existing markers on load', async ({ page }, testInfo) => {
  test.setTimeout(150000)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Footnote persistence')
  await page.getByLabel('URI', { exact: true }).fill('footnote-persistence')
  await appendModule(page, 'Text without notes')
  await expect(page.getByRole('button', { name: 'Add footnote' })).toHaveCount(0)
  await appendModule(page, 'Article with notes')

  const text = page.locator('.entry-block').last().locator('.tiptap[contenteditable=true]').first()
  const originalText = await placeCaretAtEnd(text)
  await page.getByRole('button', { name: 'Add footnote' }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  await expect(drawer).toBeVisible()
  const note = drawer.locator('.tiptap[contenteditable=true]')
  await expect(note).toBeFocused()
  await note.fill('A source with supporting material.')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Edit footnote 1', exact: true })).toBeVisible()
  await expect(text.locator('p')).toHaveText(`${originalText}1`)

  // A separate named region shares the collection UI, with its own content.
  await page.getByRole('button', { name: 'Further reading Edit blocks · Footnotes' }).click()
  await drawer.getByRole('button', { name: 'Add block', exact: true }).click()
  await expect(page.getByRole('button', { name: 'Container', exact: true })).not.toBeVisible()
  await page.getByRole('button', { name: 'Note text', exact: true }).click()
  await drawer.locator('.tiptap[contenteditable=true]').fill('Independent further reading.')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'Footnote persistence →' }).click()
  await syncLV(page)

  await expect(page.getByRole('button', { name: 'Edit footnote 1', exact: true })).toBeVisible()
  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('A source with supporting material.')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('button', { name: 'Further reading Edit blocks · Footnotes' }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('Independent further reading.')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()

  // An unrelated body edit must keep persisted note markers and note blocks.
  await page.getByLabel('Title', { exact: true }).fill('Footnote persistence edited')
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'Footnote persistence edited →' }).click()
  await expect(page.getByRole('button', { name: 'Edit footnote 1', exact: true })).toBeVisible()
  await expect(text.locator('p')).toHaveText(`${originalText}1`)
  await page.locator('.entry-block').last().screenshot({ path: testInfo.outputPath('footnote-editor.png') })

  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  await page.setViewportSize({ width: 480, height: 800 })
  await expect(drawer.locator('.block-slot-panel')).toHaveCSS('width', '480px')
  await expect(drawer.getByRole('button', { name: 'Done', exact: true })).toBeVisible()
  await drawer.screenshot({ path: testInfo.outputPath('footnote-drawer-narrow.png') })
  await page.keyboard.press('Escape')
  await expect(drawer).toHaveCount(0)
})

test('Blueprint rich text keeps its own notes across save and reload', async ({ page }) => {
  const client = await fixture(page, 'E2eProject.Projects.Client', {
    name: 'Footnote client', slug: 'footnote-client', status: 'published', language: 'en',
  })
  const project = await fixture(page, 'E2eProject.Projects.Project', {
    title: 'Field notes', slug: 'field-notes', introduction: '<p>A field with a source.</p>',
    client_id: client.id, status: 'draft', language: 'en',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  const editor = page.locator('[data-footnote-field="introduction"] .tiptap[contenteditable=true]')
  const originalText = await placeCaretAtEnd(editor)
  await page.getByRole('button', { name: 'Add footnote' }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  await expect(drawer).toBeVisible()
  await drawer.locator('.tiptap[contenteditable=true]').fill('A source belonging to the introduction.')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await expect(editor.locator('p')).toHaveText(`${originalText}1`)
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await expect(editor.locator('p')).toHaveText(`${originalText}1`)
  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('A source belonging to the introduction.')
})

test('a note uses the existing image, video and file controls and keeps media on reload', async ({ page }) => {
  test.setTimeout(120000)
  await fixture(page, 'Brando.Videos.Video', {
    title: 'Footnote film', type: 'youtube', config_target: 'default',
    source_url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', remote_id: 'dQw4w9WgXcQ',
    width: 1920, height: 1080, aspect_ratio: '1920/1080', status: 'ready',
  })
  await fixture(page, 'Brando.Files.File', {
    title: 'Footnote source', filename: 'footnote-source.pdf', filesize: 1024,
    mime_type: 'application/pdf', config_target: 'default',
  })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Footnote media')
  await page.getByLabel('URI', { exact: true }).fill('footnote-media')
  await appendModule(page, 'Article with notes')
  await page.locator('.tiptap[contenteditable=true]').first().click()
  await page.getByRole('button', { name: 'Add footnote' }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  const add = async name => {
    await drawer.getByRole('button', { name: 'Add block', exact: true }).last().click()
    await page.getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }
  await add('Note image')
  await drawer.locator('.picture-block .file-input').first().setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(drawer.locator('.picture-block .preview .image-content img')).toBeVisible({ timeout: 30000 })
  await add('Note video')
  await drawer.getByRole('button', { name: 'Select or create video' }).click()
  await page.locator('.video-picker__video', { hasText: 'Footnote film' }).click()
  await expect(drawer.locator('.video-block')).toContainText('dQw4w9WgXcQ')
  await add('Note download')
  await drawer.getByRole('button', { name: 'Add file', exact: true }).click()
  const fileDialog = page.getByRole('dialog', { name: 'File', exact: true })
  await fileDialog.getByRole('button', { name: 'Select file', exact: true }).click()
  await page.locator('.file-picker__file', { hasText: 'footnote-source.pdf' }).click()
  await fileDialog.locator('.modal-close').click()
  await expect(drawer.locator('.file-preview')).toContainText('footnote-source.pdf')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'Footnote media →' }).click()
  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  await expect(drawer.locator('.picture-block .preview .image-content img')).toBeVisible()
  await expect(drawer.locator('.video-block')).toContainText('dQw4w9WgXcQ')
  await expect(drawer.locator('.file-preview')).toContainText('footnote-source.pdf')
})
