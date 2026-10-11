import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = (await readFile(new URL('../../assets/src/authMotion.js', import.meta.url), 'utf8'))
  .replace(/import .* from '.\/motion'/, 'const prefersReducedMotion = () => window.reducedMotion;')
const { default: install } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup(t) {
  const saved = Object.fromEntries(['document', 'window', 'setTimeout', 'clearTimeout', 'getComputedStyle'].map(key => [key, globalThis[key]]))
  t.after(() => Object.assign(globalThis, saved))
  const listeners = new Map(), timers = new Map(), classes = new Set(), attributes = new Map()
  let timerId = 0, posts = 0, canceled = 0
  const animations = []
  const element = { animate: (frames, options) => { animations.push({ frames, options }); return { cancel() { canceled++ } } } }
  const login = {
    getAttribute: key => attributes.get(key), setAttribute: (key, value) => attributes.set(key, value),
    removeAttribute: key => attributes.delete(key), querySelector: () => element,
  }
  globalThis.document = {
    addEventListener: (name, callback) => listeners.set(name, callback),
    getElementById: id => id === 'application-login' ? login : element,
    documentElement: { classList: { add: (...keys) => keys.forEach(key => classes.add(key)), remove: (...keys) => keys.forEach(key => classes.delete(key)) } },
  }
  globalThis.window = { location: { origin: 'https://cms.test' }, addEventListener: (name, callback) => listeners.set(name, callback), removeEventListener: name => listeners.delete(name) }
  globalThis.getComputedStyle = () => ({ opacity: '1', transform: 'none' })
  globalThis.setTimeout = (callback, delay) => { timers.set(++timerId, { callback, delay }); return timerId }
  globalThis.clearTimeout = id => timers.delete(id)
  install()
  const submitter = { isConnected: true, hasAttribute: () => false }
  const form = {
    action: 'https://cms.test/admin/login', method: 'post', isConnected: true,
    closest: () => login, hasAttribute: key => key === 'action',
    requestSubmit(button) {
      assert.equal(button, submitter)
      const event = send()
      if (form.cancelResumed) event.preventDefault()
      if (!event.defaultPrevented) posts++
    },
  }
  const send = (extra = {}) => {
    const event = { target: form, submitter, defaultPrevented: false, preventDefault() { this.defaultPrevented = true }, ...extra }
    listeners.get('submit')(event)
    return event
  }
  const finish = () => {
    const exits = [...timers].filter(([, timer]) => timer.delay === 350)
    assert.equal(exits.length, 1)
    const [id, timer] = exits[0]
    timers.delete(id)
    timer.callback()
  }
  return { send, finish, classes, login, form, submitter, timers, animations, listeners, posts: () => posts, canceled: () => canceled }
}

test('canceled WebAuthn and LiveView submissions remain owned by their handlers', t => {
  const s = setup(t)
  s.send({ defaultPrevented: true })
  assert.equal(s.classes.has('login-submitting'), false)
  s.form.hasAttribute = key => ['action', 'phx-submit'].includes(key)
  assert.equal(s.send().defaultPrevented, false)
  assert.equal(s.animations.length, 0)
})

test('only explicit same-origin login/logout POSTs get the handoff', t => {
  const s = setup(t)
  for (const action of ['https://other.test/admin/login', 'https://cms.test/admin/login-history', 'https://cms.test/admin/reset-password']) {
    s.form.action = action
    assert.equal(s.send().defaultPrevented, false)
  }
  s.form.action = 'https://cms.test/admin/login'
  s.form.method = 'get'
  assert.equal(s.send().defaultPrevented, false)
  s.form.method = 'post'
  s.form.hasAttribute = () => false
  assert.equal(s.send().defaultPrevented, false)
  assert.equal(s.animations.length, 0)
})

test('sign-in waits one fixed exit and double clicks still send exactly one native POST', t => {
  const s = setup(t)
  assert.equal(s.send().defaultPrevented, true)
  assert.equal(s.login.getAttribute('aria-busy'), 'true')
  assert.equal(s.send().defaultPrevented, true)
  assert.equal(s.posts(), 0)
  s.finish()
  assert.equal(s.posts(), 1)
})

test('logout slides the sidebar and uses the same native form continuation', t => {
  const s = setup(t)
  s.form.action = 'https://cms.test/admin/logout'
  s.form.closest = () => null
  s.send()
  assert.equal(s.animations[0].frames[1].transform, 'translateX(-40px)')
  s.finish()
  assert.equal(s.posts(), 1)
})

test('Escape cancels a pending exit and allows a fresh attempt', t => {
  const s = setup(t)
  s.send()
  s.listeners.get('keydown')({ key: 'Escape' })
  assert.equal(s.classes.has('auth-leaving'), false)
  assert.equal(s.login.getAttribute('aria-busy'), undefined)
  assert.equal([...s.timers.values()].some(timer => timer.delay === 350), false)
  s.send()
  s.finish()
  assert.equal(s.posts(), 1)
})

for (const reason of ['validation', 'canceled', 'detached']) {
  test(`a ${reason} resumed submit restores usable controls`, t => {
    const s = setup(t)
    s.send()
    if (reason === 'validation') s.form.requestSubmit = () => {}
    if (reason === 'canceled') s.form.cancelResumed = true
    if (reason === 'detached') s.form.isConnected = false
    s.finish()
    assert.equal(s.classes.has('auth-leaving'), false)
    assert.equal(s.login.getAttribute('aria-busy'), undefined)
    assert.equal(s.posts(), 0)
  })
}

test('returning from the back-forward cache clears the departure', t => {
  const s = setup(t)
  s.send()
  s.finish()
  s.listeners.get('pageshow')({ persisted: true })
  assert.equal(s.classes.has('auth-leaving'), false)
  assert.equal(s.canceled(), 1)
})

test('reduced motion leaves native submit immediate', t => {
  const s = setup(t)
  window.reducedMotion = true
  assert.equal(s.send().defaultPrevented, false)
  assert.equal(s.animations.length, 0)
})

test('a canceled unsaved-changes prompt clears departure styling', t => {
  const s = setup(t)
  s.form.action = 'https://cms.test/admin/logout'
  s.form.closest = () => null
  s.send()
  s.finish()
  s.listeners.get('beforeunload')({ defaultPrevented: true })
  assert.equal(s.classes.has('auth-leaving'), false)
  assert.equal(s.canceled(), 3)
})
