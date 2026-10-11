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
  const element = { addEventListener() {}, querySelector() { return element } }
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
