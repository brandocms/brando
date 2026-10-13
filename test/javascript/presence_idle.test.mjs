import { test, mock } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// The lobby's away state (`assets/src/Presence/index.js`): an editor without
// input for 30 seconds, or with the tab hidden, shows as away, and is back
// on the next input or when the tab shows again. Loaded as source, with the
// window, the document and the timers stood in for.
const source = await readFile(new URL('../../assets/src/Presence/index.js', import.meta.url), 'utf8')

function setup() {
  mock.timers.enable({ apis: ['setTimeout'] })
  const listeners = {}
  const on = (event, fn) => (listeners[event] = fn)
  globalThis.window = { addEventListener: on }
  globalThis.document = { hidden: false, addEventListener: on }

  const pushed = []
  const app = { lobbyChannel: { push: (event, payload) => pushed.push([event, payload]) } }
  return { listeners, pushed, app }
}

async function presence(app) {
  const { default: Presence } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}#${Math.random()}`)
  return new Presence(app)
}

test('goes away after 30 seconds without input, and comes back on the next', async t => {
  t.after(() => mock.timers.reset())
  const { listeners, pushed, app } = setup()
  const p = await presence(app)
  p.trackIdle()
  p.trackIdle()

  mock.timers.tick(29_000)
  listeners.mousemove()
  mock.timers.tick(29_000)
  assert.deepEqual(pushed, [])

  mock.timers.tick(1_000)
  assert.deepEqual(pushed, [['user:state', { active: false }]])

  listeners.keydown()
  listeners.mousemove()
  assert.deepEqual(pushed.slice(1), [['user:state', { active: true }]])
})

test('a hidden tab is away at once, and back when it shows', async t => {
  t.after(() => mock.timers.reset())
  const { listeners, pushed, app } = setup()
  const p = await presence(app)
  p.trackIdle()

  document.hidden = true
  listeners.visibilitychange()
  assert.deepEqual(pushed, [['user:state', { active: false }]])

  mock.timers.tick(60_000)
  assert.equal(pushed.length, 1)

  document.hidden = false
  listeners.visibilitychange()
  assert.deepEqual(pushed.slice(1), [['user:state', { active: true }]])
})
