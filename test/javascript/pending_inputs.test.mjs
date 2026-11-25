import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// What a block input does while another editor's changes arrive
// (`assets/src/Presence/pendingInputs.js`, #2992). Loaded the way the other
// hook tests load unbundled, dependency-free source.
const source = await readFile(new URL('../../assets/src/Presence/pendingInputs.js', import.meta.url), 'utf8')
const { default: pendingInputs } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const block = {}

// `entry`: an entry form's rich text field, outside any block
function input(value, { richText = false, entry = false } = {}) {
  richText ||= entry
  const editor = { contains: el => el === editor.focus, dispatchEvent() {}, dataset: { tiptapType: entry ? 'rich_text' : 'block' } }
  return {
    tagName: 'INPUT',
    value,
    editor,
    classList: { contains: name => richText && name === 'tiptap-text' },
    closest: sel => (sel === '[data-block-uid]' ? (entry ? null : block) : sel === '[phx-hook="Brando.TipTap"]' && richText ? editor : null),
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

test("an entry's rich text keeps what its editor wrote while a reply to an earlier event arrives", () => {
  const { clock, inputs } = setup()
  const el = input('', { entry: true })
  clock.active = el.editor
  el.editor.focus = el.editor

  // The answer to a change made before the typing renders the field as the
  // server had it then, while the text waits on the input's debounce
  el.value = '<p>Typed</p>'
  inputs.typed(el)
  clock.now = 1100
  assert.equal(patch(inputs, el, '').value, '<p>Typed</p>')

  // The answer to its own earlier text, however late
  el.value = '<p>Typed more</p>'
  inputs.typed(el)
  clock.now = 60000
  const to = patch(inputs, el, '<p>Typed</p>')
  assert.equal(to.value, '<p>Typed more</p>')
  assert.equal(to.attribute, '<p>Typed more</p>')
})

test("an entry's rich text takes a value the server has from elsewhere", () => {
  const { clock, inputs } = setup()
  const el = input('', { entry: true })
  clock.active = el.editor
  el.editor.focus = el.editor
  el.value = '<p>Typed</p>'
  inputs.typed(el)
  clock.now = 1100
  patch(inputs, el, '<p>Typed</p>')

  // An edit handed over from another tab, with the editor still focused
  clock.now = 60000
  assert.equal(patch(inputs, el, '').value, '')
})

test("an entry's rich text takes the server's value once its editor is left", () => {
  const { clock, inputs } = setup()
  const el = input('<p>Typed</p>', { entry: true })
  inputs.typed(el)
  clock.active = null
  assert.equal(patch(inputs, el, '<p>Saved</p>').value, '<p>Saved</p>')
})

// A block element mounted again: a new element, whose inputs LiveView
// rendered from the server (#3850)
// rendered from the server, holding `inputs`: its own, and those of the
// blocks inside it, whose elements were made first
function blockElement(inputs) {
  const el = { querySelectorAll: () => inputs }
  inputs.forEach(input => (input.block ??= el))
  return el
}

// `value`: what the server rendered into it
function textInput(name, value, type = 'text') {
  const el = input(value)
  const closest = el.closest
  return Object.assign(el, {
    name,
    type,
    defaultValue: value,
    sent: [],
    closest(sel) { return sel === '[phx-hook="Brando.Block"]' ? this.block : closest(sel) },
    dispatchEvent(event) { this.sent.push([event.type, this.value]) },
    focus() { this.focused = true },
    setSelectionRange(start) {
      if (!['text', 'search', 'url', 'tel', 'password', 'textarea'].includes(this.type)) throw new Error('InvalidStateError')
      this.caret = start
    },
  })
}

test('text still on its way when its block mounts again is put back and sent from the new block', () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  const role = textInput('child_block[vars][1][value]', 'Developer')
  inputs.focused(name)
  name.value = 'Bobby'
  inputs.typed(name)

  // the element goes with the focus in it, before the debounce sends it
  clock.now = 1100
  inputs.went(blockElement([name, role]), 'uid')

  clock.now = 1300
  const newName = textInput('child_block[vars][0][value]', 'Bob')
  const newRole = textInput('child_block[vars][1][value]', 'Developer')
  inputs.came(blockElement([newName, newRole]), 'uid')

  assert.equal(newName.value, 'Bobby')
  assert.deepEqual(newName.sent, [['input', 'Bobby']])
  assert.equal(newName.focused, true)
  assert.equal(newName.caret, 5)
  // untouched, and nothing sent for it
  assert.deepEqual(newRole.sent, [])

  // once
  const again = textInput('child_block[vars][0][value]', 'Bob')
  inputs.came(blockElement([again]), 'uid')
  assert.equal(again.value, 'Bob')
})

test('a block mounted again with what was typed sends nothing, and the focus stays where it went', () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  name.value = 'Bobby'
  inputs.typed(name)
  // the editor left the field (a drag handle took the focus): its change was sent
  inputs.unfocused(name)
  inputs.focused({ tagName: 'BUTTON' })
  clock.now = 1500
  inputs.went(blockElement([name]), 'uid')

  const newName = textInput('child_block[vars][0][value]', 'Bobby')
  inputs.came(blockElement([newName]), 'uid')
  assert.deepEqual(newName.sent, [])
  assert.equal(newName.focused, undefined)
})

// Chrome takes the focus from an element as it takes it out of the page
test('an input that lost the focus as its block went gets it back in the new block', () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  inputs.focused(name)
  name.value = 'Bobby'
  inputs.typed(name)

  clock.now = 1100
  inputs.unfocused(name)
  inputs.went(blockElement([name]), 'uid')

  clock.now = 1300
  const newName = textInput('child_block[vars][0][value]', 'Bobby')
  inputs.came(blockElement([newName]), 'uid')
  assert.equal(newName.focused, true)
})

test('nothing is carried from typing long before, or to another block', () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  name.value = 'Bobby'
  inputs.typed(name)
  clock.now = 5000
  inputs.went(blockElement([name]), 'uid')
  const later = textInput('child_block[vars][0][value]', 'Bob')
  inputs.came(blockElement([later]), 'uid')
  assert.equal(later.value, 'Bob')

  inputs.typed(name)
  inputs.went(blockElement([name]), 'uid')
  const other = textInput('child_block[vars][0][value]', 'Bob')
  inputs.came(blockElement([other]), 'other')
  assert.equal(other.value, 'Bob')
})

// A multi block's children render inside its element, under the same input
// names as its own fields
test("a child block's text is carried to the child, never to its parent's field of the same name", () => {
  const { clock, inputs } = setup()
  const childVar = textInput('child_block[vars][0][value]', 'Bob')
  const child = blockElement([childVar])
  const parentVar = textInput('child_block[vars][0][value]', 'Heading')
  const parent = blockElement([parentVar, childVar])
  inputs.focused(childVar)
  childVar.value = 'Bobby'
  inputs.typed(childVar)

  clock.now = 1100
  inputs.went(parent, 'parent')
  inputs.went(child, 'child')
  // LiveView mounts the parent's hook first
  const newChildVar = textInput('child_block[vars][0][value]', 'Bob')
  const newChild = blockElement([newChildVar])
  const newParentVar = textInput('child_block[vars][0][value]', 'Heading')
  const newParent = blockElement([newParentVar, newChildVar])
  inputs.came(newParent, 'parent')
  assert.equal(newParentVar.value, 'Heading')
  assert.deepEqual(newParentVar.sent, [])
  assert.equal(newChildVar.value, 'Bob')

  inputs.came(newChild, 'child')
  assert.equal(newChildVar.value, 'Bobby')
  assert.deepEqual(newChildVar.sent, [['input', 'Bobby']])
})

test("text the server holds and another editor has since replaced is not put back over theirs", () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  clock.active = name
  inputs.focused(name)
  name.value = 'Bobby'
  inputs.typed(name)
  // the server has it, then another editor's change arrives
  clock.now = 1400
  patch(inputs, name, 'Bobby')
  clock.now = 1500
  patch(inputs, name, 'Robert')

  clock.now = 1600
  inputs.went(blockElement([name]), 'uid')
  clock.active = null
  const newName = textInput('child_block[vars][0][value]', 'Robert')
  inputs.came(blockElement([newName]), 'uid')
  assert.equal(newName.value, 'Robert')
  assert.deepEqual(newName.sent, [])
  assert.equal(newName.focused, true)
})

test("a change from another editor that comes with the move is not replaced", () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  name.value = 'Bobby'
  inputs.typed(name)
  clock.now = 1100
  inputs.went(blockElement([name]), 'uid')

  const newName = textInput('child_block[vars][0][value]', 'Robert')
  inputs.came(blockElement([newName]), 'uid')
  assert.equal(newName.value, 'Robert')
  assert.deepEqual(newName.sent, [])
})

test("a render of an earlier keystroke of this editor's is replaced", () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'Bob')
  name.value = 'Bobb'
  inputs.typed(name)
  name.value = 'Bobby'
  inputs.typed(name)
  clock.now = 1100
  inputs.went(blockElement([name]), 'uid')

  const newName = textInput('child_block[vars][0][value]', 'Bobb')
  inputs.came(blockElement([newName]), 'uid')
  assert.equal(newName.value, 'Bobby')
})

test('the focus goes back to a carried number field, which has no caret to set', () => {
  const { clock, inputs } = setup()
  const opacity = textInput('child_block[data][opacity]', '1', 'number')
  inputs.focused(opacity)
  opacity.value = '0.5'
  inputs.typed(opacity)
  clock.now = 1100
  inputs.went(blockElement([opacity]), 'uid')

  const newOpacity = textInput('child_block[data][opacity]', '1', 'number')
  inputs.came(blockElement([newOpacity]), 'uid')
  assert.equal(newOpacity.value, '0.5')
  assert.equal(newOpacity.focused, true)
  assert.equal(newOpacity.caret, undefined)
})

test("rich text still on its way is put back in the new block's input and shown by its editor", () => {
  const { clock, inputs } = setup()
  const richText = blockRichText('<p>Old</p>')
  richText.value = '<p>Old and new</p>'
  inputs.typed(richText)
  clock.now = 1100
  inputs.went(blockElement([richText]), 'uid')

  const newRichText = blockRichText('<p>Old</p>')
  inputs.came(blockElement([newRichText]), 'uid')
  assert.equal(newRichText.value, '<p>Old and new</p>')
  assert.deepEqual(newRichText.sent, [['input', '<p>Old and new</p>']])
  assert.deepEqual(newRichText.editor.events, ['brando:tiptap:sync'])
  assert.equal(newRichText.focused, undefined)
})

// A block's rich text field: a hidden input, whose value property is its
// value attribute
function blockRichText(value) {
  const el = textInput('child_block[data][text]', value, 'hidden')
  const closest = el.closest
  el.classList = { contains: name => name === 'tiptap-text' }
  el.editor.events = []
  el.editor.dispatchEvent = event => el.editor.events.push(event.type)
  el.closest = function (sel) { return sel === '[phx-hook="Brando.TipTap"]' ? this.editor : closest.call(this, sel) }
  Object.defineProperty(el, 'defaultValue', { get() { return this.value } })
  return el
}

// What the server rendered while this editor was elsewhere is what the new
// block is compared with, not a render from an earlier visit
test('text typed after coming back to a field is carried over renders from while it was elsewhere', () => {
  const { clock, inputs } = setup()
  const name = textInput('child_block[vars][0][value]', 'B')
  clock.active = name
  inputs.focused(name)
  name.value = 'Bob'
  inputs.typed(name)
  patch(inputs, name, 'Bob')

  // left, and the server's value moves on meanwhile
  clock.active = null
  inputs.left(name)
  patch(inputs, name, 'Bobb')
  name.value = name.defaultValue = 'Bobb'

  // back, typing, and the block mounts again before the debounce
  clock.now = 1500
  clock.active = name
  inputs.focused(name)
  name.value = 'Bobby'
  inputs.typed(name)
  clock.now = 1600
  inputs.went(blockElement([name]), 'uid')
  clock.active = null

  const newName = textInput('child_block[vars][0][value]', 'Bobb')
  inputs.came(blockElement([newName]), 'uid')
  assert.equal(newName.value, 'Bobby')
})

test("rich text left before its echo is not put back over another editor's newer text", () => {
  const { clock, inputs } = setup()
  const richText = blockRichText('<p>A</p>')
  richText.value = '<p>A1</p>'
  inputs.typed(richText)

  // its editor left; another editor's text arrives through ordinary patches
  inputs.left(richText)
  clock.now = 1200
  patch(inputs, richText, '<p>B1</p>')
  richText.value = '<p>B1</p>'

  clock.now = 1400
  inputs.went(blockElement([richText]), 'uid')
  const newRichText = blockRichText('<p>B2</p>')
  inputs.came(blockElement([newRichText]), 'uid')
  assert.equal(newRichText.value, '<p>B2</p>')
  assert.deepEqual(newRichText.sent, [])
})

test('a carry expires without a remount, and replacing it starts a new window', t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const { inputs } = setup()
  const carry = (uid, value) => {
    const field = textInput('name', '')
    field.value = value
    inputs.typed(field)
    inputs.went(blockElement([field]), uid)
  }
  const recover = uid => {
    const field = textInput('name', '')
    inputs.came(blockElement([field]), uid)
    return field.value
  }

  // The injected wall clock stays still. Only timer-driven removal can
  // release the deleted block before came() reads its timestamp.
  carry('deleted', 'one')
  carry('moved', 'old')
  t.mock.timers.tick(1000)
  carry('moved', 'new')
  t.mock.timers.tick(1000)
  assert.equal(recover('deleted'), '')
  assert.equal(recover('moved'), 'new')
  carry('leaving-page', 'pending')
  inputs.clear()
  assert.equal(recover('leaving-page'), '')
})
