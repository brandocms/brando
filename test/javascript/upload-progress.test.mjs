import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const source = readFileSync(new URL('../../assets/src/hooks/shared/uploadProgress.js', import.meta.url), 'utf8')
const target = { deliver_topic: 'form:example', kind: 'entry_field', field: 'cover', asset_type: 'image' }
let instance = 0
async function projection(t) {
  t.mock.method(globalThis, 'setTimeout', () => 0)
  return import(`data:text/javascript;base64,${Buffer.from(`${source}\n// ${++instance}`).toString('base64')}`)
}

test('a field shows its newest replacement and ignores late progress from the previous upload', async t => {
  const p = await projection(t)
  let state
  p.subscribeToUpload(target, value => { state = value })
  p.trackUpload('first', target)
  p.trackUpload('replacement', target)
  p.updateUpload('first', { status: 'uploading', progress: 70 })
  assert.equal(state.ref, 'replacement')
  assert.equal(state.status, 'queued')
  p.updateUpload('replacement', { status: 'done' })
  p.updateUpload('first', { status: 'done' })
  assert.equal(state.ref, 'replacement')
  assert.equal(state.status, 'done')
})

test('mixed gallery progress counts all files while preserving individual failures', async t => {
  const p = await projection(t)
  const gallery = { ...target, kind: 'entry_field_gallery' }
  let state
  p.subscribeToUpload(gallery, value => { state = value })
  p.trackUpload('photo', gallery)
  p.trackUpload('video', { ...gallery, asset_type: 'video' })
  p.trackUpload('photo2', gallery)
  p.updateUpload('photo', { status: 'done', progress: 100 })
  p.updateUpload('video', { status: 'uploading', progress: 50 })
  assert.equal(state.total, 3)
  assert.equal(state.completed, 1)
  assert.equal(state.progress, 50)
  p.updateUpload('video', { status: 'error', error: 'Video is too large' })
  p.updateUpload('photo2', { status: 'done', progress: 100 })
  assert.equal(state.status, 'error')
  assert.equal(state.completed, 2)
  assert.match(state.error, /1 of 3 uploads failed.*Video is too large/)
})

test('progress stays scoped to the field and form, including nested paths', async t => {
  const p = await projection(t)
  let state
  p.subscribeToUpload(target, value => { state = value })
  p.trackUpload('other-form', { ...target, deliver_topic: 'form:other' })
  p.trackUpload('nested-field', { ...target, path: ['items', 0] })
  assert.equal(state, null)
  p.trackUpload('current', target)
  assert.equal(state.ref, 'current')
})

test('the field and its metadata drawer observe the same manager upload', async t => {
  const p = await projection(t)
  let state
  p.subscribeToUpload({ ...target, component_id: 'project-cover' }, value => { state = value })
  p.trackUpload('drawer', target)
  p.updateUpload('drawer', { status: 'uploading', progress: 42 })
  assert.equal(state.progress, 42)
})
