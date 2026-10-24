import { test, expect } from '../../test-support/setupAuth'
import { syncLV, routeLiveSocket, dropConnection, restoreConnection } from '../../utils'

// One editor with an entry open in two tabs: one tab edits at a time
// (`BrandoAdmin.LiveView.Form.Tabs`). Every page of a context is a tab of the
// same editor, with a sessionStorage, and so a tab id, of its own.

async function project(page, title) {
  const slug = title.toLowerCase().replaceAll(' ', '-')
  const client = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'E2eProject.Projects.Client',
      attributes: { name: `${title} client`, slug: `${slug}-client`, status: 'published', language: 'en' },
      creator_id: 1,
      fields: ['id'],
    },
  })
  expect(client.ok(), await client.text()).toBeTruthy()

  const response = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'E2eProject.Projects.Project',
      attributes: {
        title,
        slug,
        client_id: (await client.json()).id,
        introduction: '<p>Opened in two tabs.</p>',
        status: 'draft',
        language: 'en',
      },
      creator_id: 1,
      fields: ['id'],
    },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  const { id } = await response.json()
  return `/admin/projects/projects/update/${id}`
}

const notice = page => page.getByTestId('tab-notice')
const title = page => page.getByLabel('Title', { exact: true })
const mainForm = page => page.locator('form.main-form')

async function open(page, url) {
  await page.goto(url)
  await syncLV(page)
}

async function editHere(page) {
  await notice(page).getByRole('button', { name: 'Edit here' }).click()
  await expect(notice(page)).toBeHidden()
  await expect(mainForm(page)).not.toHaveAttribute('inert')
}

// A duplicated tab, or a window a script opens, copies sessionStorage and
// with it the tab id: it is another tab all the same.
test('a copy of a tab is another tab', async ({ page }) => {
  const url = await project(page, 'Copied tab')
  await open(page, url)
  const [copy] = await Promise.all([
    page.waitForEvent('popup'),
    page.evaluate(href => window.open(href, '_blank'), url),
  ])
  await syncLV(copy)
  await expect(notice(copy)).toContainText('You have this entry open in another tab')
  await expect(notice(page)).toBeHidden()
  await copy.close()
})

test('a second tab opens read-only, Edit here moves editing with the unsaved title, and the first takes it back', async ({
  page,
}) => {
  const url = await project(page, 'Two tabs')
  await open(page, url)
  await expect(notice(page)).toBeHidden()

  await title(page).fill('Two tabs, typed in the first')
  await title(page).blur()
  await syncLV(page)

  const second = await page.context().newPage()
  await open(second, url)
  await expect(notice(second)).toContainText('You have this entry open in another tab')
  await expect(mainForm(second)).toHaveAttribute('inert')
  await expect(title(second)).toHaveValue('Two tabs, typed in the first')

  await editHere(second)
  await expect(notice(page)).toContainText('You are editing this entry in another tab')
  await expect(mainForm(page)).toHaveAttribute('inert')
  await expect(title(second)).toHaveValue('Two tabs, typed in the first')
  // the first tab's recovery copy is the second tab's now: nothing to offer
  await expect(second.getByTestId('draft-notice')).toBeHidden()

  // The second tab edits; the first follows
  await title(second).fill('Two tabs, typed in the second')
  await title(second).blur()
  await expect(title(page)).toHaveValue('Two tabs, typed in the second')

  // Take editing back
  await notice(page).getByRole('button', { name: 'Take editing back' }).click()
  await expect(notice(page)).toBeHidden()
  await expect(mainForm(page)).not.toHaveAttribute('inert')
  await expect(notice(second)).toContainText('You are editing this entry in another tab')
  await expect(title(page)).toHaveValue('Two tabs, typed in the second')

  await second.close()
})

test('closing the editing tab leaves the other one waiting', async ({ page }) => {
  const url = await project(page, 'Closed tab')
  const first = await page.context().newPage()
  await open(first, url)
  await open(page, url)
  await expect(notice(page)).toContainText('You have this entry open in another tab')

  await first.close()
  await expect(notice(page)).toContainText('The other tab was closed')
  // it doesn't take editing by itself
  await expect(mainForm(page)).toHaveAttribute('inert')

  await editHere(page)
})

test('a tab that comes back with offline edits after another took over makes a recovery copy, not a save', async ({
  page,
}) => {
  const url = await project(page, 'Offline tab')
  const first = await page.context().newPage()
  await routeLiveSocket(first)
  await open(first, url)
  await open(page, url)
  await expect(notice(page)).toBeVisible()

  // The first tab loses its connection and is typed into meanwhile
  await dropConnection(first)
  await title(first).fill('Typed while offline')
  await expect(notice(page)).toContainText('The other tab was closed')

  await editHere(page)

  // It edited before: it says that another tab edits now
  await restoreConnection(first)
  await expect(notice(first)).toContainText('You are editing this entry in another tab')
  await expect(mainForm(first)).toHaveAttribute('inert')

  // The editing tab offers the copy; nothing was applied or saved
  await expect(page.getByTestId('draft-notice')).toBeVisible({ timeout: 15000 })
  await expect(title(page)).toHaveValue('Offline tab')
  await page.getByRole('button', { name: 'Review recovery copy' }).click()
  await expect(page.getByTestId('draft-panel')).toContainText('Typed while offline')

  await first.close()
})

test('an upload finishing in a tab that edits no more stays in the library', async ({ page }) => {
  const url = await project(page, 'Upload elsewhere')

  // The first tab's upload frames wait until the second tab has taken over
  let hold = true
  const held = []
  await page.routeWebSocket(/\/live\/websocket/, ws => {
    const server = ws.connectToServer()
    ws.onMessage(message => {
      const upload = typeof message === 'string' ? message.includes('"lvu:') : message.includes('lvu:')
      if (hold && upload) held.push({ server, message })
      else server.send(message)
    })
  })

  await open(page, url)
  const field = page.locator('.media-field[data-asset-type=file]')
  await expect(field.getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
  await field.locator('input[type=file]').setInputFiles('./fixtures/test.pdf')

  const second = await page.context().newPage()
  await open(second, url)
  await editHere(second)
  await expect(notice(page)).toContainText('You are editing this entry in another tab')

  // The upload goes through, and finishes in the first tab
  expect(held.length).toBeGreaterThan(0)
  hold = false
  for (const { server, message } of held.splice(0)) server.send(message)

  await expect(page.locator('.toast-stack')).toContainText('It is in the library, not in the entry', { timeout: 20000 })
  await syncLV(second)
  await expect(second.locator('.media-field[data-asset-type=file]').getByRole('button', { name: 'Upload', exact: true })).toBeVisible()
  await expect(field.getByRole('button', { name: 'Upload', exact: true })).toBeVisible()

  await second.close()
})
