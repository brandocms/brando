import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { drag } from '../../test-support/richTextRows'

// An upload into a row names the row by its key as well as its index, so it
// lands in the row it was started in when the rows are reordered while it
// uploads, and in no row when its row is removed (#3899). The upload's frames
// are held on the socket until the rows have changed.

async function holdUploads(page) {
  const held = []
  let hold = true
  await page.routeWebSocket(/\/live\/websocket/, ws => {
    const server = ws.connectToServer()
    ws.onMessage(message => {
      const upload = typeof message === 'string' ? message.includes('"lvu:') : message.includes('lvu:')
      if (hold && upload) held.push(message)
      else server.send(message)
    })
    held.server = server
  })
  return {
    held,
    hold() {
      hold = true
    },
    release() {
      hold = false
      for (const message of held.splice(0)) held.server.send(message)
    },
  }
}

async function saveAndContinue(page) {
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
  await syncLV(page)
}

async function fixture(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The field's own media field; a variable's image modal holds another
const imageField = row => row.locator('.media-field[data-asset-type=image]:not([id$="-var-uploader"])')
// The toast stack is hidden in tests (setupAuth), so not by its role's accessible name
const errorToast = page => page.locator('.toast-stack[role=status] .toast--error')

test.describe('subform rows', () => {
  const rows = page => page.locator('.subform--table .subform-table-body > .subform-entry')
  const titleOf = row => row.locator('input[name$="[title]"]')
  const row = (page, title) => rows(page).filter({ has: page.locator(`input[name$="[title]"][value="${title}"]`) })

  async function twoRows(page) {
    await page.goto('/admin/projects/clients/create')
    await syncLV(page)
    await page.getByRole('textbox', { name: 'Name' }).fill('Row uploads')
    await page.getByRole('button', { name: 'Inline fields' }).click()
    await syncLV(page)
    for (const title of ['First', 'Second']) {
      const count = await rows(page).count()
      await page.locator('.subform--table').getByRole('button', { name: 'Add entry' }).click()
      await expect(rows(page)).toHaveCount(count + 1)
      await titleOf(rows(page).nth(count)).fill(title)
      await syncLV(page)
    }
  }

  test('an upload lands in its row after the rows are reordered', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)

    await imageField(rows(page).nth(0)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await drag(page, rows, 0, 1)
    await expect(titleOf(rows(page).nth(0))).toHaveValue('Second')

    uploads.release()
    await expect(imageField(row(page, 'First'))).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
    await syncLV(page)
    await expect(imageField(row(page, 'Second'))).not.toHaveAttribute('data-asset-id', /./)

  })

  test('an upload whose row was removed lands in no row, and the editor is told', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)

    await imageField(rows(page).nth(0)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await rows(page).nth(0).getByRole('button', { name: 'Remove entry' }).click()
    await expect(rows(page)).toHaveCount(1)
    await syncLV(page)

    uploads.release()
    await expect(errorToast(page)).toHaveCount(1, { timeout: 20000 })
    await syncLV(page)
    await expect(imageField(rows(page).nth(0))).not.toHaveAttribute('data-asset-id', /./)
  })

  // The drawer's own upload, finishing after the drawer is closed
  test("an upload from a row's drawer lands in its row after the rows are reordered", async ({ page }) => {
    const uploads = await holdUploads(page)
    uploads.release()
    await twoRows(page)

    const first = imageField(rows(page).nth(0))
    await first.locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect(first).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
    const original = await first.getAttribute('data-asset-id')
    await syncLV(page)

    uploads.hold()
    // A row's field is one line: its actions are in the Change menu
    await first.getByRole('button', { name: 'Change', exact: true }).click()
    await page.getByRole('button', { name: 'Configure', exact: true }).locator('visible=true').click()
    const details = page.getByRole('dialog', { name: 'Image details', exact: true })
    await expect(details).toBeVisible()
    await page.locator('#image-drawer-upload-input').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)
    // The upload manager's list covers the drawer's buttons
    await page.keyboard.press('Escape')
    await expect(details).toBeHidden()

    await drag(page, rows, 0, 1)
    await expect(titleOf(rows(page).nth(0))).toHaveValue('Second')

    uploads.release()
    await expect(imageField(row(page, 'First'))).not.toHaveAttribute('data-asset-id', original, { timeout: 20000 })
    await expect(imageField(row(page, 'First'))).toHaveAttribute('data-asset-id', /^\d+$/)
    await syncLV(page)
    await expect(imageField(row(page, 'Second'))).not.toHaveAttribute('data-asset-id', /./)
  })

  // The save gives the new row an id while the file uploads into it
  test('an upload into a new row lands in it after a save', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)
    await saveAndContinue(page)
    await page.getByRole('button', { name: 'Inline fields' }).click()
    await expect(rows(page)).toHaveCount(2)

    await page.locator('.subform--table').getByRole('button', { name: 'Add entry' }).click()
    await expect(rows(page)).toHaveCount(3)
    await titleOf(rows(page).nth(2)).fill('Third')
    await syncLV(page)

    await imageField(rows(page).nth(2)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await saveAndContinue(page)
    await expect(row(page, 'Third')).toHaveAttribute('data-row-key', /^id-/)

    uploads.release()
    await expect(imageField(row(page, 'Third'))).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
    await syncLV(page)
    await expect(errorToast(page)).toHaveCount(0)
  })
})

test.describe('block table rows', () => {
  const rows = page => page.locator('.table-rows .table-row')
  const nameOf = row => row.getByRole('textbox', { name: 'Name' })
  const row = (page, name) => rows(page).filter({ has: page.locator(`input[value="${name}"]`) })

  async function twoRows(page) {
    const table = await fixture(page, 'Brando.Content.TableTemplate', {
      name: 'Row portraits',
      vars: [
        { type: 'string', key: 'name', label: 'Name', placement: 'content', width: 'half', sequence: 0 },
        { type: 'image', key: 'portrait', label: 'Portrait', placement: 'content', width: 'half', sequence: 1 },
      ],
    })
    await fixture(page, 'Brando.Content.Module', {
      name: { en: 'Row portraits', no: 'Row portraits' }, namespace: { en: '04 TABLES', no: '04 TABELLER' },
      help_text: { en: 'A table with an image in each row' }, class: 'row-portraits', type: 'liquid',
      code: '<section>{% for row in block.table_rows %}<p>{{ row.name }}</p>{% endfor %}</section>',
      table_template_id: table.id, refs: [], vars: [], multi: false, datasource: false,
    })

    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Row portraits')
    await page.getByLabel('URI', { exact: true }).fill('row-portraits')
    await page.getByRole('button', { name: 'Add block', exact: true }).click()
    await page.getByRole('button', { name: /TABLES/ }).click()
    await page.getByRole('button', { name: 'Row portraits', exact: true }).click()
    await syncLV(page)
    for (const name of ['Alice', 'Bob']) {
      const count = await rows(page).count()
      await page.getByTestId('add-table-row').click()
      await expect(rows(page)).toHaveCount(count + 1)
      await nameOf(rows(page).nth(count)).fill(name)
      await syncLV(page)
    }
  }

  async function dragRow(page, from, to) {
    const source = await rows(page).nth(from).locator('.sort-handle').boundingBox()
    const target = await rows(page).nth(to).locator('.sort-handle').boundingBox()
    await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2)
    await page.mouse.down()
    await page.mouse.move(source.x + source.width / 2 + 12, source.y + source.height / 2, { steps: 4 })
    await page.mouse.move(target.x + target.width / 2, target.y + (to < from ? 2 : target.height - 2), { steps: 25 })
    await page.mouse.up()
    await syncLV(page)
  }

  test('an upload lands in its row after the rows are reordered', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)

    await imageField(rows(page).nth(0)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await dragRow(page, 0, 1)
    await expect(nameOf(rows(page).nth(0))).toHaveValue('Bob')

    uploads.release()
    await expect(imageField(row(page, 'Alice'))).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
    await syncLV(page)
    await expect(imageField(row(page, 'Bob'))).not.toHaveAttribute('data-asset-id', /./)
  })

  test('an upload whose row was removed lands in no row, and the editor is told', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)

    await imageField(rows(page).nth(0)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await rows(page).nth(0).getByRole('button', { name: 'Remove row' }).click()
    await expect(rows(page)).toHaveCount(1)
    await syncLV(page)

    uploads.release()
    await expect(errorToast(page)).toHaveCount(1, { timeout: 20000 })
    await syncLV(page)
    await expect(imageField(rows(page).nth(0))).not.toHaveAttribute('data-asset-id', /./)
  })

  // The page's first save gives the new rows ids while the file uploads
  test('an upload into a new row lands in it after a save', async ({ page }) => {
    const uploads = await holdUploads(page)
    await twoRows(page)

    await imageField(rows(page).nth(0)).locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
    await expect.poll(() => uploads.held.length).toBeGreaterThan(0)

    await saveAndContinue(page)
    await expect(row(page, 'Alice')).toHaveAttribute('data-table-row-key', /^id-/)

    uploads.release()
    await expect(imageField(row(page, 'Alice'))).toHaveAttribute('data-asset-id', /^\d+$/, { timeout: 20000 })
    await syncLV(page)
    await expect(imageField(row(page, 'Bob'))).not.toHaveAttribute('data-asset-id', /./)
    await expect(errorToast(page)).toHaveCount(0)
  })
})
