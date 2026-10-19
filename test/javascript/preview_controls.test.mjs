import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const source = (await readFile(new URL('../../assets/src/hooks/LivePreview/index.js', import.meta.url), 'utf8'))
  .replace("import { Dom, Events } from '@brandocms/jupiter'", 'const Dom = {}; const Events = {};')
  .replace("import { prefersReducedMotion } from '../../motion'", 'const prefersReducedMotion = () => false')
const { default: preview } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

test('keyboard resizing does not reopen a pane collapsing for standalone preview', t => {
  const previous = globalThis.window
  t.after(() => { globalThis.window = previous })
  globalThis.window = { addEventListener() {} }
  const element = { addEventListener() {}, querySelector() { return element }, closest() { return null } }
  const hook = { ...preview({}), el: element, handleEvent() {} }
  hook.mounted()
  hook.livePreviewWidth = 600
  hook.lpMaxWidth = 800
  let resized = 0
  hook.setPreviewTarget = () => { resized++ }
  hook.keyResize({ key: 'ArrowLeft', preventDefault() {} })
  assert.equal(resized, 0)
  hook.active = true
  hook.keyResize({ key: 'ArrowLeft', preventDefault() {} })
  assert.equal(resized, 1)
})

// The form's 1400px bound lifts while the preview is open (Form.css): the hook
// marks its form through LiveView's sticky JS, and only when it has one.
test('marks its form while previewing, through sticky JS', t => {
  const previous = globalThis.window
  t.after(() => { globalThis.window = previous })
  globalThis.window = { addEventListener() {} }
  const form = { classes: new Set() }
  const element = { addEventListener() {}, querySelector() { return element }, closest: selector => (selector === '.brando-form' ? form : null) }
  const js = { addClass: (el, name) => el.classes.add(name), removeClass: (el, name) => el.classes.delete(name) }
  const hook = { ...preview({}), el: element, handleEvent() {}, js: () => js }
  hook.mounted()
  hook.markPreviewing(true)
  assert.ok(form.classes.has('is-previewing'))
  hook.markPreviewing(false)
  assert.ok(!form.classes.has('is-previewing'))

  const formless = { ...preview({}), el: { ...element, closest: () => null }, handleEvent() {}, js: () => js }
  formless.mounted()
  assert.doesNotThrow(() => formless.markPreviewing(true))
})
