import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The caption popover's rich text is not part of the entry form (its input
// names a form that does not exist), and the server hears of it only on
// Save, which reads the input. A patch of the gallery while it is open
// (another image finishing processing) renders the stored caption into that
// input: the editor keeps what is being typed and puts it back in the
// input, and Save takes it without another keystroke.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// `Presence/pendingInputs.js`: how long after a keystroke a patch leaves a
// rich text's input alone
const PENDING_INPUT_MS = 2000

test('a caption being typed survives a gallery patch after a pause, and Save takes it', async ({ page }) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'CaptionTypingClient',
    slug: 'captiontypingclient',
    status: 'published',
    language: 'en',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'CaptionTypingTest',
    slug: 'captiontypingtest',
    client_id: client.id,
    introduction: '<p>Test introduction</p>',
    status: 'published',
    language: 'en',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)

  const gallery = page.locator('.gallery-input')
  const objects = gallery.locator('.gallery-object')
  const upload = gallery.getByRole('button', { name: 'Upload', exact: true })
  const chooser = page.waitForEvent('filechooser')
  await upload.click()
  await (await chooser).setFiles(['./fixtures/image.jpg'])
  await expect(objects.locator('img')).toHaveCount(1, { timeout: 30000 })
  await syncLV(page)

  await objects.first().getByRole('button', { name: 'Caption', exact: true }).click()
  const popover = gallery.locator('.gallery-text-editor')
  const editor = popover.locator('.ProseMirror')
  await expect(editor).toBeFocused()
  await page.keyboard.type('En bildetekst')
  await expect(popover.locator('input.tiptap-text')).toHaveValue('<p>En bildetekst</p>')

  // Deliberate: the pause the case is about, past the window in which a
  // patch keeps a rich text's input as typed
  await page.waitForTimeout(PENDING_INPUT_MS + 500)

  // Another image is uploaded and processed, which patches the gallery. The
  // button is clicked from script: a pointer outside the popover closes it.
  const second = page.waitForEvent('filechooser')
  await upload.evaluate(button => button.click())
  await (await second).setFiles(['./fixtures/image2.jpg'])
  await expect(objects.locator('img')).toHaveCount(2, { timeout: 30000 })
  await syncLV(page)

  await expect(popover).toBeVisible()
  await expect(editor).toHaveText('En bildetekst')
  await expect(popover.locator('input.tiptap-text')).toHaveValue('<p>En bildetekst</p>')

  // Saved without typing again
  await popover.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(popover).toHaveCount(0)
  await objects.first().getByRole('button', { name: 'Caption', exact: true }).click()
  await expect(editor).toHaveText('En bildetekst')

  expect(errors).toEqual([])
})
