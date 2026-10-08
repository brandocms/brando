import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// The save button and ⌘S save by pushing the entry form's fields, not by
// submitting the form (`assets/src/hooks/Form/saveForm.js`). Loaded as the
// other hook tests load unbundled, dependency-free source.
const source = await readFile(new URL('../../assets/src/hooks/Form/saveForm.js', import.meta.url), 'utf8')
const { default: saveForm } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

function setup(t, { saveEvent = 'save_form', active = null } = {}) {
  const pushed = []
  const dispatched = []
  const saveSource = { id: 'page_form-save-source' }
  const wrapper = { querySelector: selector => (selector === '[data-save-source]' ? saveSource : null) }
  const inputs = [{ name: 'page[title]' }, { name: 'page[uri]' }]
  const form = {
    dataset: saveEvent ? { saveEvent } : {},
    elements: inputs,
    values: [['page[title]', 'Title'], ['upload', { file: true }]],
    closest: () => wrapper,
    dispatchEvent: event => dispatched.push(event),
  }
  t.mock.method(globalThis, 'FormData', function (form) { return form.values })
  const previous = globalThis.document
  globalThis.document = { activeElement: active, body: {} }
  t.after(() => { globalThis.document = previous })
  const hook = {
    js: () => ({ push: (el, event, { value }) => pushed.push({ el, event, value }) }),
    pushEventTo: (el, event, value) => pushed.push({ el, event, value, fromHook: true }),
  }
  return { hook, form, inputs, saveSource, pushed, dispatched }
}

test('pushes the fields from the save source, not the hook element, with the token', t => {
  const s = setup(t)
  saveForm(s.hook, s.form, { token: 7 })
  assert.deepEqual(s.pushed, [{ el: s.saveSource, event: 'save_form', value: { form: 'page%5Btitle%5D=Title', token: 7 } }])
})

test('⌘S says in the same push to stay, instead of pushing that from the hook element', t => {
  const s = setup(t)
  saveForm(s.hook, s.form, { stay: true })
  assert.deepEqual(s.pushed, [{ el: s.saveSource, event: 'save_form', value: { form: 'page%5Btitle%5D=Title', stay: true } }])
})

test('marks the form submitted, so errors show for untouched fields, and tells the recovery copy', t => {
  const s = setup(t)
  saveForm(s.hook, s.form)
  for (const input of s.inputs) assert.equal(input.phxPrivate['phx-has-submitted'], true)
  assert.equal(s.form.phxPrivate['phx-has-submitted'], true)
  assert.deepEqual(s.dispatched.map(event => event.type), ['brando:save'])
})

test('flushes the focused input with a blur marked as a flush, keeping the focus', t => {
  const events = []
  const input = { tagName: 'INPUT', dispatchEvent: event => events.push(event) }
  const s = setup(t, { active: input })
  saveForm(s.hook, s.form)
  assert.equal(events.length, 1)
  assert.equal(events[0].type, 'blur')
  assert.equal(events[0].brandoFlush, true)
  assert.equal(globalThis.document.activeElement, input)
})

test("flushes a widget's hidden input when its editor has the focus", t => {
  const events = []
  const hidden = { dispatchEvent: event => events.push(event) }
  const editor = { tagName: 'DIV', closest: () => ({ querySelector: () => hidden }) }
  const s = setup(t, { active: editor })
  saveForm(s.hook, s.form)
  assert.deepEqual(events.map(event => event.type), ['blur'])
})

test('a form that takes no save event is submitted', t => {
  const s = setup(t, { saveEvent: null })
  saveForm(s.hook, s.form)
  assert.deepEqual(s.pushed, [])
  assert.deepEqual(s.dispatched.map(event => event.type), ['submit'])
})
