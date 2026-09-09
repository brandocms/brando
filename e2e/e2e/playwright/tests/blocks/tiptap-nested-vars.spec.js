import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function fixture(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function moduleWithHtmlVars(page) {
  const table = await fixture(page, 'Brando.Content.TableTemplate', {
    name: 'Linked locations',
    vars: [
      { type: 'html', key: 'city', label: 'City', placement: 'content', width: 'full', sequence: 0, value: '<p>Oslo</p>' },
      { type: 'string', key: 'caption', label: 'Caption', placement: 'content', width: 'full', sequence: 1 },
    ],
  })
  return fixture(page, 'Brando.Content.Module', {
    name: { en: 'Linked locations', no: 'Linked locations' }, namespace: { en: '04 TABLES', no: '04 TABELLER' },
    help_text: { en: 'Rich text in variables and table rows' }, class: 'linked-locations', type: 'liquid',
    code: '<section>{{ introduction }}{% for row in block.table_rows %}<p>{{ row.city }} {{ row.caption }}</p>{% endfor %}</section>',
    table_template_id: table.id, refs: [], multi: false, datasource: false,
    vars: [{ type: 'html', key: 'introduction', label: 'Introduction', placement: 'content', width: 'full', value: '<p>Our locations</p>' }],
  })
}

async function link(page, field, url) {
  const editor = field.locator('.ProseMirror')
  await editor.click()
  await editor.press('ControlOrMeta+a')
  await field.getByRole('button', { name: 'Link', exact: true }).click()
  const dialog = page.locator('#tiptap-link-dialog')
  await expect(dialog).toBeVisible()
  await dialog.getByLabel('Destination', { exact: true }).fill(url)
  await dialog.getByRole('button', { name: 'Apply link', exact: true }).click()
  // Closing requires a successful acknowledgement from this same editor.
  await expect(dialog).not.toBeVisible()
  await expect(editor.locator('a')).toHaveAttribute('href', url)
}

test('table-row and block-variable links survive other edits, save and reload', async ({ page }) => {
  await moduleWithHtmlVars(page)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Nested editor links')
  await page.getByLabel('URI', { exact: true }).fill('nested-editor-links')
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: /TABLES/ }).click()
  await page.getByRole('button', { name: 'Linked locations', exact: true }).click()
  await syncLV(page)
  await page.getByTestId('add-table-row').click()
  await page.getByTestId('add-table-row').click()
  const rows = page.locator('.table-rows .table-row')
  await expect(rows).toHaveCount(2)
  const first = rows.nth(0).locator('.tiptap-wrapper'), second = rows.nth(1).locator('.ProseMirror')
  await second.click()
  await second.press('ControlOrMeta+a')
  await page.keyboard.type('Bergen')
  await expect(second).toHaveText('Bergen')
  await link(page, first, '/oslo')
  await expect(first.locator('.ProseMirror')).toHaveText('Oslo')
  await expect(second).toHaveText('Bergen')
  await rows.nth(0).getByLabel('Caption', { exact: true }).fill('Visit us')
  await syncLV(page)
  const introduction = page.locator('.block-vars .tiptap-wrapper')
  await link(page, introduction, '/locations')
  await page.getByLabel('Title', { exact: true }).fill('Nested editor links updated')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'Nested editor links updated', exact: true }).click()
  await syncLV(page)
  await expect(first.locator('.ProseMirror a')).toHaveAttribute('href', '/oslo')
  await expect(second).toHaveText('Bergen')
  await expect(rows.nth(0).getByLabel('Caption', { exact: true })).toHaveValue('Visit us')
  await expect(introduction.locator('.ProseMirror a')).toHaveAttribute('href', '/locations')

  // Cancellation must retain the saved link, and removal must acknowledge too.
  await first.locator('.ProseMirror a').click()
  await first.getByRole('button', { name: 'Edit link', exact: true }).click()
  const dialog = page.locator('#tiptap-link-dialog')
  await dialog.getByLabel('Destination', { exact: true }).fill('/discarded')
  await dialog.getByRole('button', { name: 'Cancel', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await expect(first.locator('.ProseMirror a')).toHaveAttribute('href', '/oslo')
  await first.getByRole('button', { name: 'Edit link', exact: true }).click()
  await dialog.getByRole('button', { name: 'Remove link', exact: true }).click()
  await expect(dialog).not.toBeVisible()
  await expect(first.locator('.ProseMirror a')).toHaveCount(0)
})

test('module-variable default link targets the LiveView through nested components', async ({ page }) => {
  const module = await moduleWithHtmlVars(page)
  await page.goto(`/admin/config/content/modules/update/${module.id}`)
  await syncLV(page)
  await page.getByRole('tab', { name: /^Variables/ }).click()
  await page.getByRole('button', { name: 'Edit variable introduction', exact: true }).click()
  const variable = page.locator('#module-default-var-0')
  await variable.getByRole('tab', { name: 'Default value', exact: true }).click()
  const field = variable.locator('.tiptap-wrapper')
  await link(page, field, '/locations')
  await expect(field.locator('.ProseMirror')).toHaveText('Our locations')
  await variable.getByRole('button', { name: 'Done', exact: true }).click()
  await page.getByRole('button', { name: 'Save (⇧⌘S)', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/config\/content\/modules$/)
  await page.goto(`/admin/config/content/modules/update/${module.id}`)
  await syncLV(page)
  await page.getByRole('tab', { name: /^Variables/ }).click()
  await page.getByRole('button', { name: 'Edit variable introduction', exact: true }).click()
  await variable.getByRole('tab', { name: 'Default value', exact: true }).click()
  await expect(field.locator('.ProseMirror a')).toHaveAttribute('href', '/locations')
})
