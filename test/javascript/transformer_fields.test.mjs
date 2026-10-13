import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = await readFile(new URL('../../assets/src/hooks/TransformerFields/index.js', import.meta.url), 'utf8')
const { default: TransformerFields } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const input = (name, value, extra = {}) => ({
  name: `transformer_item[${name}]`, value, tagName: 'INPUT', type: 'text',
  matches() { return this.disabled || false },
  ...extra,
})

function setup(t) {
  const previous = globalThis.document
  globalThis.document = new EventTarget()
  const hooks = []
  t.after(() => {
    hooks.forEach(hook => hook.destroyed())
    globalThis.document = previous
  })
  t.mock.timers.enable({ apis: ['setTimeout'] })
  const calls = []
  const row = (domId, controls) => {
    const hook = Object.assign(TransformerFields(), {
      el: Object.assign(new EventTarget(), {
        dataset: { domId, target: '7' },
        querySelectorAll: () => controls,
      }),
      pushEventTo(target, event, payload) { calls.push({ target, event, ...payload }) },
    })
    hook.mounted()
    hooks.push(hook)
    return hook
  }
  return { calls, row, tick: ms => t.mock.timers.tick(ms) }
}

function change(hook, control, type = 'input') {
  let intercepted = false
  hook.onEvent({ target: control, type, stopPropagation() { intercepted = true } })
  return intercepted
}

const params = call => [...new URLSearchParams(call.params)]

test('translation edits send the whole field once on save, scoped to their own row', t => {
  const { calls, row, tick } = setup(t)
  const en = input('label][en', 'New English')
  const no = input('label][no', 'Norsk')
  const de = input('label][de', 'Größe & Maße', { type: 'hidden' })
  const first = row('first', [en, no, de, input('title', 'Unrelated')])
  const other = input('label][en', 'Second row')
  const second = row('second', [other])

  assert.equal(change(first, en), true)
  tick(200)
  no.value = 'Ny norsk'
  change(first, no)
  change(second, other)
  assert.deepEqual(calls, [])
  document.dispatchEvent(new Event('brando:flush'))

  assert.equal(calls.length, 2)
  assert.deepEqual(params(calls[0]), [
    [en.name, en.value], [no.name, no.value], [de.name, de.value],
  ])
  assert.deepEqual(params(calls[1]), [[other.name, other.value]])
  assert.deepEqual(calls.map(({ dom_id, field, event, target }) => ({ dom_id, field, event, target })), [
    { dom_id: 'first', field: 'label', event: 'update_field', target: '7' },
    { dom_id: 'second', field: 'label', event: 'update_field', target: '7' },
  ])
  tick(300)
  assert.equal(calls.length, 2)
})

test('textarea translations debounce and keep sibling values, including an explicitly cleared language', t => {
  const { calls, row, tick } = setup(t)
  const en = input('description][en', '', { tagName: 'TEXTAREA', type: 'textarea' })
  const no = input('description][no', 'Linje 1\nLinje 2', { tagName: 'TEXTAREA', type: 'textarea' })
  const hook = row('first', [en, no])
  change(hook, en)
  tick(299)
  assert.deepEqual(calls, [])
  tick(1)
  assert.deepEqual(params(calls[0]), [[en.name, ''], [no.name, no.value]])
})

test('array edits send every current member and preserve a final empty control when cleared', t => {
  const { calls, row } = setup(t)
  const controls = [input('aliases][', 'One'), input('aliases][', 'Two'), input('aliases][', '')]
  const hook = row('first', controls)
  controls[2].value = 'Three'
  change(hook, controls[2], 'change')
  assert.deepEqual(params(calls[0]).map(([, value]) => value), ['One', 'Two', 'Three'])

  controls.splice(1, 1)
  change(hook, controls[0], 'change')
  assert.deepEqual(params(calls[1]).map(([, value]) => value), ['One', 'Three'])

  controls.splice(1)
  controls[0].value = ''
  change(hook, controls[0], 'change')
  assert.deepEqual(params(calls[2]), [['transformer_item[aliases][]', '']])
})

test('explicit array selections bypass stale controls and remain scoped to their own row and field', t => {
  const { calls, row } = setup(t)
  const title = input('title', 'Pending title')
  const first = row('first', [input('tags][', 'red', { type: 'hidden' }), title])
  const second = row('second', [input('tags][', 'blue', { type: 'hidden' })])
  change(first, title)
  const select = (hook, values) => hook.el.dispatchEvent(new CustomEvent('brando:array-selection', {
    cancelable: true, detail: { name: 'transformer_item[tags][]', values },
  }))

  assert.equal(select(first, ['red', 'green & gold']), false)
  assert.equal(select(first, []), false)
  assert.equal(select(second, ['blue', 'red']), false)
  document.dispatchEvent(new Event('brando:flush'))

  assert.deepEqual(calls.map(({ dom_id, field }) => ({ dom_id, field })), [
    { dom_id: 'first', field: 'tags' },
    { dom_id: 'first', field: 'tags' },
    { dom_id: 'second', field: 'tags' },
    { dom_id: 'first', field: 'title' },
  ])
  assert.deepEqual(calls.map(params), [
    [['transformer_item[tags][]', 'red'], ['transformer_item[tags][]', 'green & gold']],
    [['transformer_item[tags][]', '']],
    [['transformer_item[tags][]', 'blue'], ['transformer_item[tags][]', 'red']],
    [[title.name, title.value]],
  ])
})

test('explicit selections work before controls are patched; unrelated names and unmounted rows are ignored', t => {
  const { calls, row } = setup(t)
  const hook = row('first', [])
  const selection = name => new CustomEvent('brando:array-selection', {
    cancelable: true, detail: { name, values: ['green'] },
  })

  assert.equal(hook.el.dispatchEvent(selection('client[tags][]')), true)
  assert.deepEqual(calls, [])
  assert.equal(hook.el.dispatchEvent(selection('transformer_item[tags][]')), false)
  assert.deepEqual(params(calls[0]), [['transformer_item[tags][]', 'green']])
  hook.destroyed()
  assert.equal(hook.el.dispatchEvent(selection('transformer_item[tags][]')), true)
  assert.equal(calls.length, 1)
})

test('scalar controls, checkbox fallbacks, radio groups and multiple selects follow form submission', t => {
  const { calls, row } = setup(t)
  const title = input('title', 'A title')
  const unchecked = input('featured', 'true', { type: 'checkbox', checked: false })
  const checked = input('size', 'large', { type: 'radio', checked: true })
  const selected = input('tags][', '', {
    tagName: 'SELECT', type: 'select-multiple', multiple: true,
    selectedOptions: [
      { value: 'a', disabled: false, matches: () => false },
      { value: 'b', disabled: false, matches: () => false },
      { value: 'disabled', disabled: true, matches: () => true },
    ],
  })
  const hook = row('first', [
    title, input('featured', 'false', { type: 'hidden' }), unchecked,
    input('size', 'small', { type: 'radio', checked: false }), checked, selected,
    input('title', 'Disabled', { disabled: true }),
  ])

  change(hook, title, 'change')
  change(hook, unchecked, 'change')
  change(hook, checked, 'change')
  change(hook, selected, 'change')
  selected.selectedOptions = []
  change(hook, selected, 'change')
  assert.deepEqual(calls.map(params), [
    [[title.name, title.value]],
    [[unchecked.name, 'false']],
    [[checked.name, 'large']],
    [[selected.name, 'a'], [selected.name, 'b']],
    [[selected.name, '']],
  ])
})

test('unrelated and disabled controls are ignored; unmount cancels pending edits', t => {
  const { calls, row, tick } = setup(t)
  const title = input('title', 'Unsaved')
  const disabled = input('label][en', 'Disabled', { disabled: true })
  const hook = row('first', [title, disabled])
  assert.equal(change(hook, { name: 'client[name]' }), false)
  assert.equal(change(hook, disabled), false)
  change(hook, title)
  hook.destroyed()
  tick(300)
  assert.deepEqual(calls, [])
})
