import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'

// The keyboard shortcut registry (`assets/src/shortcuts/registry.js`), loaded
// as the other hook tests load unbundled, dependency-free source.
const source = await readFile(new URL('../../assets/src/shortcuts/registry.js', import.meta.url), 'utf8')
const registry = await import(`data:text/javascript;base64,${Buffer.from(source).toString('base64')}`)
const {
  SHORTCUTS,
  GROUPS,
  createSequencer,
  displayKeys,
  find,
  inDialog,
  isCharacterShortcut,
  isMacPlatform,
  isTextTarget,
  matches,
  matchesChord,
} = registry

const key = (k, mods = {}) => ({ key: k, code: '', metaKey: false, ctrlKey: false, altKey: false, shiftKey: false, ...mods })

test('every shortcut has a unique id, a known group and keys or a sequence', () => {
  const ids = SHORTCUTS.map(s => s.id)
  assert.equal(new Set(ids).size, ids.length)
  for (const shortcut of SHORTCUTS) {
    assert.ok(GROUPS.includes(shortcut.group), shortcut.id)
    assert.ok(Array.isArray(shortcut.keys) !== Array.isArray(shortcut.sequence), shortcut.id)
  }
})

test('plain keys stay to ? and g sequences, apart from the listing', () => {
  const singles = SHORTCUTS.filter(s => s.keys && isCharacterShortcut(s))
  assert.deepEqual(singles.filter(s => s.group !== 'listing').map(s => s.id), ['help'])
  for (const shortcut of SHORTCUTS.filter(s => s.sequence)) assert.equal(shortcut.sequence[0], 'g', shortcut.id)
})

test('every sequence is reachable: no two share their keys', () => {
  const sequences = SHORTCUTS.filter(s => s.sequence).map(s => s.sequence.join(' '))
  assert.equal(new Set(sequences).size, sequences.length)
})

test('Mod is ⌘ or Ctrl, and Shift must match', () => {
  assert.ok(matches('save', key('s', { metaKey: true })))
  assert.ok(matches('save', key('s', { ctrlKey: true })))
  assert.ok(!matches('save', key('S', { metaKey: true, shiftKey: true })))
  assert.ok(matches('save-close', key('S', { metaKey: true, shiftKey: true })))
  assert.ok(!matches('save', key('s')))
  assert.ok(!matches('save', key('s', { metaKey: true, altKey: true })))
  assert.ok(matches('palette', key('k', { ctrlKey: true })))
  assert.ok(!matches('palette', key('k', { ctrlKey: true, shiftKey: true })))
})

test('a letter typed with Alt is read from its code, as a Mac types another character', () => {
  assert.ok(matchesChord('Mod+Alt+M', key('µ', { metaKey: true, altKey: true, code: 'KeyM' })))
  assert.ok(!matchesChord('Mod+Alt+M', key('µ', { metaKey: true, code: 'KeyM' })))
})

test('? matches with or without Shift, but not with a modifier', () => {
  assert.ok(matches('help', key('?', { shiftKey: true })))
  assert.ok(matches('help', key('?')))
  assert.ok(!matches('help', key('?', { ctrlKey: true })))
})

test('g then d completes a sequence', () => {
  const seq = createSequencer()
  assert.deepEqual(seq.feed(key('g')), { pending: true })
  assert.equal(seq.pending, 'g')
  assert.deepEqual(seq.feed(key('d')), { id: 'go-dashboard' })
  assert.equal(seq.pending, null)
})

test('a sequence waits only so long for its second key', () => {
  let now = 0
  const seq = createSequencer({ timeout: 1500, now: () => now })
  seq.feed(key('g'))
  now = 1600
  assert.equal(seq.feed(key('d')), null)
})

test('a key that completes nothing ends the wait', () => {
  const seq = createSequencer()
  seq.feed(key('g'))
  assert.equal(seq.feed(key('x')), null)
  assert.equal(seq.feed(key('d')), null)
})

test('g then c is Configuration, c alone a new entry', () => {
  const seq = createSequencer()
  seq.feed(key('g'))
  assert.deepEqual(seq.feed(key('c')), { id: 'go-configuration' })
  assert.deepEqual(seq.feed(key('c')), { id: 'new-entry' })
})

test('g twice starts over, and the sequence still completes', () => {
  const seq = createSequencer()
  seq.feed(key('g'))
  assert.deepEqual(seq.feed(key('g')), { pending: true })
  assert.deepEqual(seq.feed(key('s')), { id: 'go-search' })
})

test('a modifier cancels a sequence, and Shift on its own changes nothing', () => {
  const seq = createSequencer()
  seq.feed(key('g'))
  assert.equal(seq.feed(key('Shift', { shiftKey: true })), null)
  assert.equal(seq.pending, 'g')
  assert.equal(seq.feed(key('d', { metaKey: true })), null)
  assert.equal(seq.pending, null)
})

test('? opens the sheet', () => {
  assert.deepEqual(createSequencer().feed(key('?', { shiftKey: true })), { id: 'help' })
})

test('Shift+G does not start a sequence', () => {
  assert.equal(createSequencer().feed(key('G', { shiftKey: true })), null)
})

test('reset forgets a pending key', () => {
  const seq = createSequencer()
  seq.feed(key('g'))
  seq.reset()
  assert.equal(seq.feed(key('d')), null)
})

test('keys are written for the platform', () => {
  assert.deepEqual(displayKeys(find('save-close'), true), [['⇧', '⌘', 'S']])
  assert.deepEqual(displayKeys(find('save-close'), false), [['Ctrl', 'Shift', 'S']])
  assert.deepEqual(displayKeys(find('add-note'), true), [['⌥', '⌘', 'M']])
  assert.deepEqual(displayKeys(find('add-note'), false), [['Ctrl', 'Alt', 'M']])
  assert.deepEqual(displayKeys(find('go-dashboard'), true), [['G', 'D']])
  assert.deepEqual(displayKeys(find('menu-move'), false), [['↑'], ['↓']])
  assert.deepEqual(displayKeys(find('close'), false), [['Esc']])
  assert.ok(isMacPlatform('MacIntel'))
  assert.ok(isMacPlatform('macOS'))
  assert.ok(!isMacPlatform('Linux x86_64'))
  assert.ok(!isMacPlatform('Windows'))
})

// A stand-in for an element: its tag, input type and the selectors it is inside
function el({ tag = 'div', type, editable = false, inside = [] } = {}) {
  return {
    tagName: tag.toUpperCase(),
    type,
    isContentEditable: editable,
    closest: selector => (selector.split(',').some(part => inside.includes(part.trim())) ? {} : null),
  }
}

test('typing targets: text inputs, textareas, selects, rich text and CodeMirror', () => {
  assert.ok(isTextTarget(el({ tag: 'input', type: 'text' })))
  assert.ok(isTextTarget(el({ tag: 'input', type: 'search' })))
  assert.ok(isTextTarget(el({ tag: 'textarea' })))
  assert.ok(isTextTarget(el({ tag: 'select' })))
  assert.ok(isTextTarget(el({ editable: true })))
  assert.ok(isTextTarget(el({ inside: ['.cm-editor'] })))
  assert.ok(isTextTarget(el({ inside: ['.ProseMirror'] })))
  assert.ok(!isTextTarget(el({ tag: 'input', type: 'checkbox' })))
  assert.ok(!isTextTarget(el({ tag: 'button' })))
  assert.ok(!isTextTarget(null))
})

test('focus in a dialog, a modal or a drawer', () => {
  assert.ok(inDialog(el({ inside: ['dialog[open]'] })))
  assert.ok(inDialog(el({ inside: ['.modal'] })))
  assert.ok(inDialog(el({ inside: ['[role="dialog"]'] })))
  assert.ok(!inDialog(el()))
})

test('a shortcut skips a disabled or inert target', () => {
  const el = ({ disabled = false, inert = false } = {}) => ({
    matches: selector => selector === ':disabled' && disabled,
    closest: selector => (selector === '[inert]' && inert ? {} : null),
  })
  const usable = el()
  assert.equal(registry.firstUsable([el({ disabled: true }), el({ inert: true }), usable]), usable)
  assert.equal(registry.firstUsable([el({ disabled: true })]), null)
  assert.equal(registry.firstUsable([]), null)
})

// The runtime (`assets/src/shortcuts/index.js`) with the registry inlined,
// fresh for each test: the page's choice is module state.
const runtimeSource = (await readFile(new URL('../../assets/src/shortcuts/index.js', import.meta.url), 'utf8')).replace(
  "from './registry'",
  `from 'data:text/javascript;base64,${Buffer.from(source).toString('base64')}'`
)
let runtimeLoads = 0

async function withStorage(storage, fn) {
  const saved = { document: globalThis.document, localStorage: globalThis.localStorage }
  globalThis.document = { querySelector: () => null }
  globalThis.localStorage = storage
  try {
    const fresh = `${runtimeSource}\n// load ${++runtimeLoads}\n`
    await fn(await import(`data:text/javascript;base64,${Buffer.from(fresh).toString('base64')}`))
  } finally {
    Object.assign(globalThis, saved)
  }
}

const memoryStorage = (overrides = {}) => {
  const items = new Map()
  return {
    getItem: k => (items.has(k) ? items.get(k) : null),
    setItem: (k, v) => items.set(k, String(v)),
    removeItem: k => items.delete(k),
    ...overrides,
  }
}

const denied = () => {
  throw new Error('storage denied')
}

test('turning character keys off lasts for the page when storage is unavailable', async () => {
  await withStorage({ getItem: denied, setItem: denied, removeItem: denied }, runtime => {
    assert.equal(runtime.characterKeysEnabled(), true)
    runtime.setCharacterKeysEnabled(false)
    assert.equal(runtime.characterKeysEnabled(), false)
    runtime.setCharacterKeysEnabled(true)
    assert.equal(runtime.characterKeysEnabled(), true)
  })
})

test('turning character keys off lasts for the page when the store is full', async () => {
  await withStorage(memoryStorage({ setItem: denied }), runtime => {
    runtime.setCharacterKeysEnabled(false)
    assert.equal(runtime.characterKeysEnabled(), false)
  })
})

test('a stored choice is read from storage, so another tab can change it', async () => {
  const storage = memoryStorage()
  await withStorage(storage, runtime => {
    runtime.setCharacterKeysEnabled(false)
    assert.equal(runtime.characterKeysEnabled(), false)
    storage.removeItem('brando:shortcuts:character-keys:anonymous')
    assert.equal(runtime.characterKeysEnabled(), true)
  })
})
