import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// What a block input does while another editor's changes arrive
// (`assets/src/Presence/pendingInputs.js`, #2992). Loaded the way the other
// hook tests load unbundled, dependency-free source.
const source = await readFile(new URL('../../assets/src/Presence/pendingInputs.js', import.meta.url), 'utf8')
const { default: pendingInputs } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const block = {}

function input(value, { richText = false } = {}) {
  const editor = { contains: el => el === editor.focus, dispatchEvent() {} }
  return {
    tagName: 'INPUT',
    value,
    editor,
    classList: { contains: name => richText && name === 'tiptap-text' },
    closest: sel => (sel === '[data-block-uid]' ? block : sel === '[phx-hook="Brando.TipTap"]' && richText ? editor : null),
    setAttribute() {},
    querySelectorAll: () => [],
  }
}

function setup() {
  const clock = { now: 1000, active: null }
  const inputs = pendingInputs({ now: () => clock.now, activeElement: () => clock.active })
  return { clock, inputs }
}

const patch = (inputs, el, value) => {
  const to = { value, setAttribute(_name, v) { this.attribute = v } }
  inputs.patching(el, to)
  return to
}

test("the server's answers to this editor's own keystrokes never come back when it leaves", () => {
  const { clock, inputs } = setup()
  const el = input('')
  clock.active = el

  el.value = 'Hello'
  inputs.typed(el)
  el.value = 'Hello world'
  clock.now = 1040
  inputs.typed(el)
  // the answer to "Hello" arrives after the last keystroke, then the one to
  // "Hello world"; LiveView keeps the focused input's value either way
  clock.now = 1050
  patch(inputs, el, 'Hello')
  clock.now = 1300
  patch(inputs, el, 'Hello world')

  clock.active = null
  clock.now = 2000
  inputs.left(el)
  assert.equal(el.value, 'Hello world')
})

test("an own answer that is not the latest is not taken, even without a later equal one", () => {
  const { clock, inputs } = setup()
  const el = input('')
  clock.active = el

  el.value = 'Hel'
  inputs.typed(el)
  el.value = 'Hello'
  clock.now = 1100
  inputs.typed(el)
  clock.now = 1200
  patch(inputs, el, 'Hel')

  clock.active = null
  inputs.left(el)
  assert.equal(el.value, 'Hello')
})

test("another editor's value is taken when this editor leaves without typing again", () => {
  const { clock, inputs } = setup()
  const el = input('Mine')
  clock.active = el
  inputs.typed(el)

  clock.now = 1500
  patch(inputs, el, 'Theirs')
  assert.equal(el.value, 'Mine')

  clock.active = null
  clock.now = 1600
  inputs.left(el)
  assert.equal(el.value, 'Theirs')
})

test("typing after another editor's value arrived keeps this editor's", () => {
  const { clock, inputs } = setup()
  const el = input('Mine')
  clock.active = el

  patch(inputs, el, 'Theirs')
  clock.now = 1100
  el.value = 'Mine, later'
  inputs.typed(el)

  clock.active = null
  inputs.left(el)
  assert.equal(el.value, 'Mine, later')
})

test('a value equal to the input clears what was noted before it', () => {
  const { clock, inputs } = setup()
  const el = input('Mine')
  clock.active = el

  patch(inputs, el, 'Theirs')
  // the server ends up holding what is shown (this editor's change won)
  clock.now = 1100
  patch(inputs, el, 'Mine')

  clock.active = null
  inputs.left(el)
  assert.equal(el.value, 'Mine')
})

test("a rich text input keeps what was typed against an older own value, and notes another editor's", () => {
  const { clock, inputs } = setup()
  const el = input('', { richText: true })
  clock.active = {}
  el.editor.focus = clock.active

  el.value = '<p>Hello</p>'
  inputs.typed(el)
  el.value = '<p>Hello world</p>'
  inputs.typed(el)

  // well past the typing window: an own answer still never replaces it
  clock.now = 5000
  const own = patch(inputs, el, '<p>Hello</p>')
  assert.equal(own.value, '<p>Hello world</p>')

  // another editor's value while typing is kept back, then taken on leaving
  clock.now = 5100
  el.value = '<p>Hello world!</p>'
  inputs.typed(el)
  clock.now = 5200
  const theirs = patch(inputs, el, '<p>Theirs</p>')
  assert.equal(theirs.value, '<p>Hello world!</p>')

  clock.active = null
  el.editor.focus = null
  clock.now = 5300
  inputs.left(el)
  assert.equal(el.value, '<p>Theirs</p>')
})

test('inputs outside blocks and without the focus are left to LiveView', () => {
  const { clock, inputs } = setup()
  const outside = { ...input('Mine'), closest: () => null }
  clock.active = outside
  assert.equal(patch(inputs, outside, 'Theirs').value, 'Theirs')

  const unfocused = input('Mine')
  clock.active = null
  patch(inputs, unfocused, 'Theirs')
  inputs.left(unfocused)
  assert.equal(unfocused.value, 'Mine')
})
