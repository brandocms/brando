import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// A change a widget holds back (the colour picker while it is dragged), that
// a save asks for at once (`assets/src/hooks/Form/pendingChange.js`).
const source = await readFile(new URL('../../assets/src/hooks/Form/pendingChange.js', import.meta.url), 'utf8')
const { default: pendingChange, FLUSH_EVENT } = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)

const clock = t => {
  t.mock.timers.enable({ apis: ['setTimeout'] })
  return ms => t.mock.timers.tick(ms)
}

test('the last change goes once its input settles', t => {
  const tick = clock(t)
  const seen = []
  const change = pendingChange(colour => seen.push(colour), 100)
  change('#111111')
  change('#222222')
  tick(99)
  assert.deepEqual(seen, [])
  tick(1)
  assert.deepEqual(seen, ['#222222'])
})

test('a save asks for the change held back, and it goes at once, once', t => {
  const tick = clock(t)
  const seen = []
  const change = pendingChange(colour => seen.push(colour), 100)
  change('#333333')
  change.flush()
  assert.deepEqual(seen, ['#333333'])
  tick(200)
  assert.deepEqual(seen, ['#333333'])
})

test('with nothing held back, a flush does nothing; a cancel drops what is held', t => {
  const tick = clock(t)
  const seen = []
  const change = pendingChange(colour => seen.push(colour), 100)
  change.flush()
  change('#444444')
  change.cancel()
  tick(200)
  change.flush()
  assert.deepEqual(seen, [])
  assert.equal(FLUSH_EVENT, 'brando:flush')
})
