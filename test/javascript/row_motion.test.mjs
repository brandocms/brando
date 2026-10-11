import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// Exercise ownership and insertion order separately from the browser's
// measured animation tests. The only animation dependency records its row.
const source = (await readFile(new URL('../../assets/src/hooks/TableRows/index.js', import.meta.url), 'utf8'))
  .replace("import revealRow from '../../rowMotion'", 'const revealRow = (row, removing = false) => { row.revealed++; row.removing = removing }')
const { default: tableRows } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

for (const action of ['insert', 'add']) test(`nested ${action} does not change the next outer reveal`, t => {
  const previous = globalThis.MutationObserver
  globalThis.MutationObserver = class {
    observe() {}
    disconnect() {}
  }
  t.after(() => { globalThis.MutationObserver = previous })
  const listeners = {}
  const outer = { dataset: {}, contains: () => true, addEventListener: (name, fn) => { listeners[name] = fn } }
  const inner = {}
  const row = () => ({ parentElement: { closest: () => outer }, revealed: 0 })
  const first = row()
  const second = row()
  let rows = [first, second]
  outer.querySelectorAll = () => rows
  const hook = { ...tableRows(), el: outer }
  hook.mounted()

  // Plain inner Add sits outside its own hook, but within the outer one.
  // Inner Insert is inside its own hook and points to its own row.
  const nestedButton = {
    closest: selector => selector.includes('phx-hook') ? (action === 'insert' ? inner : outer) : (action === 'insert' ? {} : first),
  }
  const buttonClass = action === 'insert' ? '.subform-insert' : '.add-entry-button'
  listeners.click({ target: { closest: selector => selector.includes(buttonClass) ? nestedButton : null } })
  hook.reveal()

  // Plain subforms' Add button sits beside their list hook; the inserted row
  // arrives without a click on the hook itself.
  const added = row()
  rows = [...rows, added]
  hook.reveal()
  assert.equal(added.revealed, 1)
  assert.equal(first.revealed + second.revealed, 0)
})

test('every row in a batch addition reveals instead of leaving', () => {
  const rows = [{ revealed: 0 }, { revealed: 0 }, { revealed: 0 }]
  const hook = { ...tableRows(), count: 0, rows: () => rows }
  hook.reveal()
  assert.ok(rows.every(row => row.revealed === 1 && row.removing === false))
})
