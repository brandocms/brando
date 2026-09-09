import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

const root = new URL('../../assets/src/components/TipTap/', import.meta.url)
async function moduleFromSource(name) {
  const source = (await readFile(new URL(name, root), 'utf8')).replace("'./capabilities.json'", JSON.stringify(new URL('capabilities.json', root).href))
  return import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
}
const { normalizeUrl, isAllowedUri, linkRel } = await moduleFromSource('urlPolicy.js')
const { resolveCapabilities, addPreset, presets, normalizeStyles } = await moduleFromSource('config.js')
const urls = JSON.parse(await readFile(new URL('../fixtures/rich_text/urls.json', import.meta.url)))

test('client URL policy matches the server contract fixtures', () => {
  for (const fixture of urls) {
    assert.equal(isAllowedUri(fixture.input), fixture.allowed, fixture.input)
    assert.equal(normalizeUrl(fixture.input), fixture.normalized, fixture.input)
  }
  assert.equal(linkRel('_blank', 'nofollow sponsored'), 'nofollow sponsored noopener noreferrer')
  assert.equal(linkRel(null, null), null)
})
test('presets add to explicit configuration; empty and legacy all differ', () => {
  assert.deepEqual(resolveCapabilities([]), [])
  assert.deepEqual(resolveCapabilities(''), [])
  assert.deepEqual(resolveCapabilities([null]), resolveCapabilities('all'))
  assert.ok(addPreset(['color'], 'caption').includes('color'))
  assert.ok(addPreset([], 'basic').includes('orderedList'))
  for (const values of Object.values(presets)) assert.ok(!values.includes('blockquote'))
})
test('style keys are injective for punctuation and case, and labels do not affect identity', () => {
  const styles = ['foo-bar', 'foo_bar', 'Foo-bar'].map(className => ({ element: 'span', class: className, label: 'Same label' }))
  const normalized = normalizeStyles(styles)
  assert.equal(new Set(normalized.map(style => style.markName)).size, 3)
  assert.deepEqual(normalized.map(style => style.className), styles.map(style => style.class))
  assert.equal(normalizeStyles([{ ...styles[0], label: 'Renamed' }])[0].markName, normalized[0].markName)
  assert.equal(normalizeStyles([...styles, styles[0]]).length, 3)
})
