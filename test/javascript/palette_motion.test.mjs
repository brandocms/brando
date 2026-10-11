import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const motion = (await readFile(new URL('../../assets/src/nativeDialogMotion.js', import.meta.url), 'utf8')).replace("import { motionDuration, prefersReducedMotion } from './motion'", 'const motionDuration = () => 300; const prefersReducedMotion = () => false;')
const motionURL = `data:text/javascript;base64,${Buffer.from(motion).toString('base64')}`
const source = (await readFile(new URL('../../assets/src/hooks/CommandPalette/index.js', import.meta.url), 'utf8'))
  .replace("import { bindShortcut } from '../../shortcuts'", 'const bindShortcut = () => () => {};')
  .replace("import { motionDuration, prefersReducedMotion } from '../../motion'", 'const motionDuration = () => 300; const prefersReducedMotion = () => false;')
  .replace("'../../nativeDialogMotion'", JSON.stringify(motionURL))
const { default: palette } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('closing cancels Enter waiting for a search reply during the exit', t => {
  const previous = globalThis.setTimeout
  t.after(() => { globalThis.setTimeout = previous })
  globalThis.setTimeout = () => 0
  let activated = 0
  const hook = { ...palette(), dialog: { open: true }, js: () => ({ removeAttribute() {} }), pendingEnter: { newTab: false }, query: 'old', results: { dataset: { query: 'new' } }, input: { value: 'new' }, mark() {}, activate() { activated++ } }
  hook.close()
  hook.sync()
  assert.equal(activated, 0)
  assert.equal(hook.pendingEnter, null)
})

test('a click on a fading result cannot navigate', t => {
  const saved = { window: globalThis.window, MutationObserver: globalThis.MutationObserver }
  t.after(() => Object.assign(globalThis, saved))
  globalThis.window = { addEventListener() {} }
  globalThis.MutationObserver = class { observe() {} }
  const listeners = {}
  const element = { dataset: {}, querySelector: () => element, addEventListener: (name, fn) => { listeners[name] = fn } }
  const hook = { ...palette(), el: element, rememberSoon() {} }
  hook.mounted()
  hook.closing = true
  let prevented = false
  let stopped = false
  listeners.click({ target: {}, preventDefault() { prevented = true }, stopPropagation() { stopped = true } })
  assert.equal(prevented, true)
  assert.equal(stopped, true)
})

test('typing during loading waits for its own search, not a stale data-query', t => {
  const saved = globalThis.window
  t.after(() => { globalThis.window = saved })
  globalThis.window = { location: { pathname: '/admin' } }
  const box = { getBoundingClientRect: () => ({ height: 10 }), animate: () => ({ finished: Promise.resolve(), cancel() {} }) }
  const pushes = []
  let activated = 0
  const hook = {
    ...palette(),
    dialog: { open: true },
    // Left over from an earlier opening: it already names the typed text.
    results: { ...box, dataset: { query: 'Palette delayed entry' } },
    body: box,
    input: { value: 'Palette delayed entry' },
    openVersion: 0,
    pendingEnter: { newTab: false },
    query: '',
    js: () => ({ setAttribute() {}, removeAttribute() {} }),
    readRecent: () => [],
    mark() {},
    activate() { activated++ },
    pushEvent: (event, payload, reply) => pushes.push({ event, payload, reply }),
  }
  hook.beginLoading()
  hook.requestOpen()

  // The opening's reply carries the rows for an empty query.
  pushes[0].reply()
  assert.equal(activated, 0)
  assert.equal(hook.loading, true)
  assert.deepEqual(pushes.map(push => push.event), ['open', 'search'])
  assert.equal(pushes[1].payload.q, 'Palette delayed entry')

  pushes[1].reply()
  assert.equal(hook.loading, false)
  assert.equal(activated, 1)
})
