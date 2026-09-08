import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// The library ships unbundled source for consumer Vite builds, without a root
// ESM package declaration. Load that exact, dependency-free hook for Node tests.
const source = await readFile(new URL('../../assets/src/hooks/Form/draftRecovery.js', import.meta.url), 'utf8')
const { default: draftRecovery } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function editor(t) {
  t.mock.timers.enable({ apis: ['setTimeout', 'Date'], now: 100000 })
  const listeners = new Map()
  const handlers = new Map()
  const sent = []
  const main = { values: [['page[title]', 'Working title']], matches: () => true }
  const block = { id: 'entry_block_form-abc', values: [['entry_block[text]', 'Focused text']] }
  let connected = true
  const el = {
    dataset: { draftEnabled: 'true', draftFormId: 'page_form' },
    querySelector: () => main,
    querySelectorAll: () => [block],
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
  }
  t.mock.method(globalThis, 'FormData', function (form) { return form.values })
  const previousWindow = globalThis.window
  t.after(() => {
    if (previousWindow === undefined) delete globalThis.window
    else globalThis.window = previousWindow
  })
  globalThis.window = {
    addEventListener: (name, fn) => listeners.set(name, fn),
    removeEventListener: name => listeners.delete(name),
  }
  const hook = {
    el,
    liveSocket: { isConnected: () => connected },
    pushEventTo: (_el, event, payload) => sent.push({ event, ...payload }),
    handleEvent: (name, fn) => handlers.set(name, fn),
    js: () => ({ addClass() {}, removeClass() {} }),
  }
  const recovery = draftRecovery(hook)
  const emit = (name, data = {}) => handlers.get(`b:draft-${name}`)({ id: 'page_form', ...data })
  const pending = () => {
    let prevented = false
    listeners.get('beforeunload')({ preventDefault: () => { prevented = true } })
    return prevented
  }
  return {
    sent, main, recovery, emit, pending,
    tick: ms => t.mock.timers.tick(ms),
    input: () => listeners.get('input')({ target: { closest: () => main } }),
    submit: () => listeners.get('submit')({ target: main }),
    ack: (request = sent.at(-1)) => emit('saved', request),
    disconnect() { connected = false; recovery.disconnected() },
    reconnect() { connected = true; recovery.reconnected() },
  }
}

test('idle editors and clean reconnects send no recovery captures', t => {
  const e = editor(t)
  e.tick(60000)
  e.disconnect()
  e.reconnect()
  e.tick(60000)
  assert.equal(e.sent.length, 0)
  assert.equal(e.pending(), false)
})

test('captures visible raw input once, three seconds after the last change', t => {
  const e = editor(t)
  e.input()
  e.tick(2000)
  e.main.values.push(['page[password]', 'excluded'])
  e.input()
  e.tick(2999)
  assert.equal(e.sent.length, 0)
  e.tick(1)
  assert.equal(e.sent.length, 1)
  assert.equal(e.sent[0].main, 'page%5Btitle%5D=Working+title')
  assert.equal(e.sent[0].blocks.abc, 'entry_block%5Btext%5D=Focused+text')
  e.ack()
  e.tick(60000)
  assert.equal(e.sent.length, 1)
  assert.equal(e.pending(), false)
})

test('continuous edits are captured at least every fifteen seconds', t => {
  const e = editor(t)
  for (let second = 0; second < 45; second++) {
    e.main.values = [['page[title]', `Edit ${second}`]]
    e.input()
    e.tick(1000)
    if ((second + 1) % 15 === 0) {
      assert.equal(e.sent.length, (second + 1) / 15)
      assert.equal(new URLSearchParams(e.sent.at(-1).main).get('page[title]'), `Edit ${second}`)
      e.ack()
    }
  }
  assert.equal(e.sent.length, 3)
})

test('server-owned changes schedule capture without DOM input', t => {
  const e = editor(t)
  e.emit('dirty')
  e.tick(3000)
  assert.equal(e.sent.length, 1)
  e.ack()
  e.tick(60000)
  assert.equal(e.sent.length, 1)
})

test('an acknowledgement preserves input edited while the capture was in flight', t => {
  const e = editor(t)
  e.input()
  e.tick(3000)
  e.tick(1000)
  e.input()
  e.ack()
  assert.equal(e.pending(), true)
  e.tick(2999)
  assert.equal(e.sent.length, 1)
  e.tick(1)
  assert.equal(e.sent.length, 2)
  e.ack()
  assert.equal(e.pending(), false)
})

test('an ignored or failed capture retries, and a late acknowledgement cannot acknowledge its replacement', t => {
  const e = editor(t)
  e.input()
  e.tick(3000)
  e.tick(11000)
  assert.equal(e.sent.length, 2)
  e.ack(e.sent[0])
  assert.equal(e.pending(), true)
  e.ack()
  assert.equal(e.pending(), false)
  e.tick(60000)
  assert.equal(e.sent.length, 2)
})

test('successful Save cancels outstanding capture work and ignores its late reply', t => {
  const e = editor(t)
  e.input()
  e.tick(3000)
  e.submit()
  e.emit('reset', { clean: true })
  e.ack()
  assert.equal(e.pending(), false)
  e.tick(60000)
  assert.equal(e.sent.length, 1)
})

test('Save cannot acknowledge newer browser input that has not reached server validation yet', t => {
  const e = editor(t)
  e.input()
  e.tick(3000)
  e.submit()
  e.input()
  e.emit('reset', { clean: true })
  e.tick(3000)
  assert.equal(e.sent.length, 2)
  e.ack(e.sent[0])
  assert.equal(e.pending(), true)
  e.ack()
  assert.equal(e.pending(), false)
})

test('a reset with newer server changes keeps work pending', t => {
  const e = editor(t)
  e.input()
  e.submit()
  e.emit('reset', { clean: false })
  e.tick(3000)
  assert.equal(e.sent.length, 1)
  assert.equal(e.pending(), true)
})

test('offline input stays pending and is captured immediately on reconnect', t => {
  const e = editor(t)
  e.disconnect()
  e.input()
  e.tick(60000)
  assert.equal(e.sent.length, 0)
  assert.equal(e.pending(), true)
  e.reconnect()
  assert.equal(e.sent.length, 1)
  e.ack()
  assert.equal(e.pending(), false)
  e.disconnect()
  e.reconnect()
  assert.equal(e.sent.length, 1)
})

test('destroy removes scheduled work and listeners', t => {
  const e = editor(t)
  e.input()
  e.recovery.destroy()
  e.tick(60000)
  assert.equal(e.sent.length, 0)
})
