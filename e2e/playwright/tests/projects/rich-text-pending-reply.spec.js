import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The answer to an earlier event renders a rich text field's hidden input as
// the server had it then. Arriving while newer text still waits on the
// input's 300 ms debounce, it put the older value back, the debounce sent
// that, and the editor went on showing text the form no longer had: a save
// lost it, and so did a recovery copy taken meanwhile.

// Holds the server's frames from `hold()` until `release()`, in order, and
// resolves `sent(predicate)` with the next frame to the server it matches.
const replies = async page => {
  const sockets = []
  const waiting = []
  let holding = false
  await page.routeWebSocket('**/live/websocket*', socket => {
    const entry = { socket, held: [] }
    sockets.push(entry)
    const server = socket.connectToServer()
    server.onMessage(message => (holding ? entry.held.push(message) : socket.send(message)))
    socket.onMessage(message => {
      server.send(message)
      for (const wait of waiting.splice(0)) wait.predicate(String(message)) ? wait.resolve() : waiting.push(wait)
    })
  })
  return {
    hold: () => { holding = true },
    release: () => {
      holding = false
      for (const entry of sockets) entry.held.splice(0).forEach(message => entry.socket.send(message))
    },
    sent: predicate => new Promise(resolve => waiting.push({ predicate, resolve })),
  }
}

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('text typed while the answer to earlier text is on its way stays in the field and is saved', async ({ page }) => {
  const socket = await replies(page)
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Reply client', slug: 'reply-client', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Pending reply', slug: 'pending-reply', client_id: client.id, introduction: '<p>Saved.</p>', status: 'published', language: 'en',
  })
  const path = `/admin/projects/projects/update/${project.id}`
  // Page time runs as usual until paused below
  await page.clock.install()
  await page.goto(path)
  await syncLV(page)
  const editor = page.getByRole('textbox', { name: 'Introduction', exact: true })
  const introduction = page.locator('input[name="project[introduction]"]')

  // The debounce sends "First."; its answer waits while more is typed
  socket.hold()
  const first = socket.sent(frame => frame.includes('"validate"') && frame.includes('project%5Bintroduction%5D=%3Cp%3EFirst.%3C%2Fp%3E'))
  await editor.fill('First.')
  await first

  // With page time paused, the debounce of the newer text cannot fire before
  // the answer to "First." is applied, however slow the machine
  await page.clock.pauseAt(await page.evaluate(() => Date.now() + 500))
  await editor.fill('First. Then more.')
  await expect(introduction).toHaveValue('<p>First. Then more.</p>')
  socket.release()
  await expect(page.locator('.phx-change-loading')).toHaveCount(0)
  await page.clock.resume()

  await syncLV(page)
  await expect(introduction).toHaveValue('<p>First. Then more.</p>')
  await expect(editor).toHaveText('First. Then more.')

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/projects\/projects$/)
  await page.goto(path)
  await syncLV(page)
  await expect(editor).toHaveText('First. Then more.')
})
