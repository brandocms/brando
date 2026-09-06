import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.setTimeout(120000)

const fixture = async (page, schema, attributes) => {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const setText = async (page, editor, text) => {
  await editor.click()
  await expect(editor).toBeFocused()
  await editor.press('ControlOrMeta+a')
  await editor.press('Backspace')
  await page.keyboard.insertText(text)
  await expect(editor).toHaveText(text)
}

const addModule = async (page, name) => {
  await page.locator('.blocks-wrapper:not(.footnote-storage) > .blocks-content > .block-plus-wrapper button.block-plus').click()
  await page.getByRole('button', { name, exact: true }).click()
  await syncLV(page)
}

const createPage = async (page, title) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill(title)
  await page.getByLabel('URI', { exact: true }).fill(title.toLowerCase().replaceAll(' ', '-'))
}

const savePage = async (page, title) => {
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: `${title} →`, exact: true }).click()
  await syncLV(page)
}

test('a renamed region keeps its content through remap, collaboration, recovery and save', async ({ page, secondUserPage }, testInfo) => {
  const module = await fixture(page, 'Brando.Content.Module', {
    name: { en: 'Recoverable region', no: 'Recoverable region' },
    namespace: { en: '09 NOTES & REGIONS', no: '09 NOTES & REGIONS' },
    help_text: { en: 'Region recovery fixture' }, class: 'recoverable-region', type: 'liquid',
    code: '<aside>{% ref refs.sidebar %}</aside>', multi: false, datasource: false,
    refs: [{ name: 'sidebar', description: 'Reading', uid: 'recoverable-region-ref', data: { type: 'blocks', data: { module_set: 'Footnotes' } } }],
    vars: [],
  })
  const title = 'Recover a region'
  await createPage(page, title)
  await addModule(page, 'Recoverable region')
  await page.getByRole('button', { name: 'Reading Edit blocks · Footnotes', exact: true }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  await drawer.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: 'Note text', exact: true }).click()
  await setText(page, drawer.locator('.tiptap[contenteditable=true]'), 'Original region content')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await savePage(page, title)
  const entryUrl = page.url()
  const uid = await page.locator('[data-block-slot]').getAttribute('data-block-slot')

  await page.goto(`/admin/config/content/modules/update/${module.id}`)
  await page.getByRole('tab', { name: /^References/ }).click()
  await page.getByRole('button', { name: 'Edit reference sidebar', exact: true }).click()
  const refDialog = page.locator('#module-default-ref-0')
  await refDialog.getByLabel('Template name').fill('related')
  await refDialog.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('tab', { name: /^Template/ }).click()
  await page.locator('.cm-content:visible').click()
  await page.keyboard.press('ControlOrMeta+a')
  await page.keyboard.insertText('<aside>{% ref refs.related %}</aside>')
  await page.getByTestId('submit').click()
  await page.locator('#module-destructive-modal').getByRole('button', { name: 'Save anyway', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules$/)

  await page.goto(entryUrl)
  const unused = page.locator('.unused-collections')
  await expect(unused).toContainText('sidebar')
  await expect(page.locator(`[data-block-slot="${uid}"]`)).toHaveCount(1)
  await unused.getByRole('button', { name: 'Open', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('Original region content')
  await setText(page, drawer.locator('.tiptap[contenteditable=true]'), 'Recovered with my unsaved edit')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await secondUserPage.goto(entryUrl)
  await expect(secondUserPage.locator('.unused-collections')).toBeVisible()

  await unused.getByRole('button', { name: 'Remap', exact: true }).click()
  await unused.getByLabel('Move this content to an empty region').selectOption('related')
  await unused.screenshot({ path: testInfo.outputPath('unused-region.png') })
  await unused.getByRole('button', { name: 'Remap region', exact: true }).click()
  await expect(unused).toHaveCount(0)
  await expect(page.locator(`[data-block-slot="${uid}"] input[name$="[slot_name]"]`)).toHaveValue('related')
  await expect(secondUserPage.locator('.unused-collections')).toHaveCount(0)
  await expect(secondUserPage.locator(`[data-block-slot="${uid}"] input[name$="[slot_name]"]`)).toHaveValue('related')

  await expect(page.getByTestId('draft-status')).toContainText('Recovery copy saved at', { timeout: 25000 })
  await page.reload()
  await page.getByRole('button', { name: 'Review recovery copy', exact: true }).click()
  await page.getByRole('button', { name: 'Restore recovery copy', exact: true }).click()
  await expect(page.getByTestId('draft-panel')).toHaveCount(0)
  await expect(page.locator(`[data-block-slot="${uid}"] input[name$="[slot_name]"]`)).toHaveValue('related')
  await savePage(page, title)
  await expect(unused).toHaveCount(0)
  await page.getByRole('button', { name: 'Reading Edit blocks · Footnotes', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('Recovered with my unsaved edit')
  await expect(page.locator(`[data-block-slot="${uid}"]`)).toHaveCount(1)
})

test('an unreferenced block note can be restored, deleted, undone and saved', async ({ page }) => {
  const title = 'Recover a block note'
  await createPage(page, title)
  await addModule(page, 'Article with notes')
  const editor = page.locator('.entry-block .tiptap[contenteditable=true]').first()
  await setText(page, editor, 'Body text')
  await page.getByRole('button', { name: 'Add footnote', exact: true }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  await setText(page, drawer.locator('.tiptap[contenteditable=true]'), 'Keep this source')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await savePage(page, title)
  const uid = await page.locator('.tiptap-footnote').getAttribute('data-footnote-uid')
  await setText(page, editor, 'Body without a reference')
  await editor.blur()
  const unused = page.locator('.unused-collections')
  await expect(unused).toContainText('Keep this source')
  await unused.getByRole('button', { name: 'Restore reference', exact: true }).click()
  await expect(page.locator(`.tiptap-footnote[data-footnote-uid="${uid}"]`)).toHaveCount(1)
  await expect(unused).toHaveCount(0)
  await setText(page, editor, 'Body without a reference')
  await editor.blur()
  await unused.getByRole('button', { name: 'Delete', exact: true }).click()
  await expect(page.locator(`[data-block-slot="${uid}"]`)).toHaveCount(0)
  await page.getByTestId('block-bin').getByRole('button', { name: 'Undo', exact: true }).click()
  await expect(unused).toBeVisible()
  await unused.getByRole('button', { name: 'Open', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('Keep this source')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await unused.getByRole('button', { name: 'Delete', exact: true }).click()
  await savePage(page, title)
  await expect(unused).toHaveCount(0)
  await expect(page.locator(`[data-block-slot="${uid}"]`)).toHaveCount(0)
})

test('Blueprint notes expose the same recovery controls beside their text field', async ({ page }, testInfo) => {
  const client = await fixture(page, 'E2eProject.Projects.Client', { name: 'Note client', slug: 'note-client', status: 'published', language: 'en' })
  const project = await fixture(page, 'E2eProject.Projects.Project', {
    title: 'Unused field note', slug: 'unused-field-note', introduction: '<p>Introduction</p>',
    client_id: client.id, status: 'draft', language: 'en',
  })
  const url = `/admin/projects/projects/update/${project.id}`
  await page.goto(url)
  const editor = page.locator('[data-footnote-field="introduction"] .tiptap[contenteditable=true]')
  await editor.click()
  await page.getByRole('button', { name: 'Add footnote', exact: true }).click()
  const drawer = page.locator('.block-slot-drawer.visible')
  await setText(page, drawer.locator('.tiptap[contenteditable=true]'), 'An introduction source')
  await drawer.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(url)
  const uid = await page.locator('.tiptap-footnote').getAttribute('data-footnote-uid')
  await setText(page, editor, 'Rewritten introduction')
  await editor.blur()
  const unused = page.locator('#project_introduction-unused-notes .unused-collections')
  await expect(unused).toContainText('An introduction source')
  await unused.screenshot({ path: testInfo.outputPath('unused-note.png') })
  await unused.getByRole('button', { name: 'Restore reference', exact: true }).click()
  await expect(page.locator(`.tiptap-footnote[data-footnote-uid="${uid}"]`)).toHaveCount(1)
  await expect(unused).toHaveCount(0)
  await setText(page, editor, 'Rewritten introduction')
  await editor.blur()
  await unused.getByRole('button', { name: 'Delete', exact: true }).click()
  await expect(page.locator(`[data-block-slot="${uid}"]`)).toHaveCount(0)
  await page.getByTestId('block-bin').getByRole('button', { name: 'Undo', exact: true }).click()
  await expect(unused).toContainText('An introduction source')
  await unused.getByRole('button', { name: 'Restore reference', exact: true }).click()
  await page.getByRole('button', { name: 'Save (⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(url)
  await expect(unused).toHaveCount(0)
  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  await expect(drawer.locator('.tiptap[contenteditable=true]')).toHaveText('An introduction source')
})
