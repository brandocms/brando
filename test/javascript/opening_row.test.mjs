import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// The listing row an entry opens from (`assets/src/openingRow.js`), loaded as
// the other hook tests load unbundled, dependency-free source.
const source = await readFile(new URL('../../assets/src/openingRow.js', import.meta.url), 'utf8')
const { default: installOpeningRows, openingRow } = await import(
  `data:text/javascript;base64,${Buffer.from(source).toString('base64')}`
)

const HREF = 'http://localhost/admin/pages/update/6'

function setup({ linkClass = 'phx-click-loading', href = HREF } = {}) {
  const row = { isConnected: true, classes: new Set(), attrs: {} }
  const link = {
    href,
    classList: new Set(linkClass ? [linkClass] : []),
    closest: (selector) => (selector === '.child-row, .list-row' ? row : null),
  }
  const doc = {
    querySelectorAll: (selector) =>
      selector === 'a.phx-click-loading[data-phx-link="redirect"]' && link.classList.has('phx-click-loading') ? [link] : [],
  }
  const listeners = {}
  const win = { addEventListener: (name, fn) => { listeners[name] = fn } }
  // LiveView's JS commands: sticky, so a patch of the listing keeps them
  const liveSocket = {
    js: () => ({
      addClass: (el, name) => el.classes.add(name),
      removeClass: (el, name) => el.classes.delete(name),
      setAttribute: (el, name, value) => { el.attrs[name] = value },
      removeAttribute: (el, name) => { delete el.attrs[name] },
    }),
  }
  installOpeningRows(liveSocket, win, doc)
  const fire = (name, detail) => listeners[name]({ detail, persisted: detail?.persisted })
  return { row, link, doc, fire }
}

test('the row of the link LiveView navigates from is marked opening', () => {
  const { row, fire } = setup()
  fire('phx:page-loading-start', { kind: 'redirect', to: HREF })
  assert.ok(row.classes.has('is-opening'))
  assert.equal(row.attrs['aria-busy'], 'true')
})

test('a patch, another link or a click LiveView did not mark leaves the rows alone', () => {
  for (const [options, detail] of [
    [{}, { kind: 'patch', to: HREF }],
    [{}, { kind: 'redirect', to: 'http://localhost/admin/pages/update/7' }],
    [{ linkClass: null }, { kind: 'redirect', to: HREF }],
  ]) {
    const { row, fire } = setup(options)
    fire('phx:page-loading-start', detail)
    assert.equal(row.classes.size, 0)
  }
})

test('the mark comes off when the navigation ends, however it ends', () => {
  for (const [name, detail] of [
    ['phx:page-loading-stop', { kind: 'redirect', to: HREF }],
    ['phx:page-loading-stop', { kind: 'error', to: HREF }],
    ['pageshow', { persisted: true }],
  ]) {
    const { row, fire } = setup()
    fire('phx:page-loading-start', { kind: 'redirect', to: HREF })
    fire(name, detail)
    assert.equal(row.classes.has('is-opening'), false, name)
    assert.equal(row.attrs['aria-busy'], undefined, name)
  }
})

test("an event's own loading state is not the navigation ending", () => {
  const { row, fire } = setup()
  fire('phx:page-loading-start', { kind: 'redirect', to: HREF })
  fire('phx:page-loading-stop', { kind: 'element', to: HREF })
  assert.ok(row.classes.has('is-opening'))
})

test('openingRow finds nothing without a marked link', () => {
  const { doc } = setup({ linkClass: null })
  assert.equal(openingRow(HREF, doc), null)
})
