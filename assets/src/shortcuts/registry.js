/**
 * Every keyboard shortcut in the admin, in one list.
 *
 * The keyboard shortcut sheet (`?`) is drawn from this list, so a shortcut
 * that is not here is not on the sheet, and one that is here is either
 * handled from it or tested against it:
 *
 * - `dispatch: true`: `shortcuts/index.js` listens for it, on one capturing
 *   `keydown` on the window, and runs its handler: a built-in one (the sheet,
 *   "go to", new entry, preview) or one a hook binds while it is mounted
 *   (`bindShortcut`: the command palette, the listing's filter).
 * - The rest belong to the widget that has the keys: the entry form's save
 *   (`hooks/Form`, which matches with `matches()` from here), the rich text
 *   editor (TipTap), menus (`hooks/FloatingDropdown`) and the module picker
 *   (`hooks/ModulePickerKeys`). They are listed so the sheet shows them.
 *
 * Keys: `keys` are alternatives, each a chord such as `Mod+Shift+S`, where
 * `Mod` is ⌘ on a Mac and Ctrl elsewhere. `sequence` is pressed one key after
 * the other, within `SEQUENCE_TIMEOUT` ms.
 *
 * Screen readers: in browse mode NVDA and JAWS use single letters to move
 * around the page, and a page cannot tell when browse mode is on. So the
 * only plain-letter shortcuts are `?` and sequences that begin with `g`, plus
 * the listing's `f` and `c`, which only exist on a listing. They never fire in
 * a text field or while a dialog has the focus, and the sheet can turn all of
 * them off (WCAG 2.1.4, character key shortcuts); the modified ones (⌘K, ⌘S)
 * stay on.
 *
 * This file has no imports, so the unit tests can load it as it is
 * (`test/javascript/shortcuts.test.mjs`).
 */

export const SEQUENCE_TIMEOUT = 1500

export const GROUPS = ['global', 'listing', 'entry', 'block']

export const SHORTCUTS = [
  // Global
  { id: 'help', group: 'global', keys: ['?'], dispatch: true },
  { id: 'palette', group: 'global', keys: ['Mod+K'], dispatch: true, inText: true, inModal: true },
  { id: 'go-dashboard', group: 'global', sequence: ['g', 'd'], dispatch: true, href: '/admin' },
  { id: 'go-search', group: 'global', sequence: ['g', 's'], dispatch: true, href: '/admin/search', always: true },
  { id: 'go-assistant', group: 'global', sequence: ['g', 'a'], dispatch: true, href: '/admin/assistant' },
  { id: 'go-configuration', group: 'global', sequence: ['g', 'c'], dispatch: true, menu: 'configuration' },
  { id: 'go-images', group: 'global', sequence: ['g', 'i'], dispatch: true, href: '/admin/assets/images' },
  { id: 'go-users', group: 'global', sequence: ['g', 'u'], dispatch: true, href: '/admin/users' },
  { id: 'menu-move', group: 'global', keys: ['ArrowUp', 'ArrowDown'] },
  { id: 'close', group: 'global', keys: ['Escape'] },

  // Listing
  { id: 'filter', group: 'listing', keys: ['f'], dispatch: true },
  { id: 'new-entry', group: 'listing', keys: ['c'], dispatch: true },

  // Entry editor
  { id: 'save', group: 'entry', keys: ['Mod+S'] },
  { id: 'save-close', group: 'entry', keys: ['Mod+Shift+S'] },
  { id: 'preview', group: 'entry', sequence: ['g', 'p'], dispatch: true },
  { id: 'bold', group: 'entry', keys: ['Mod+B'] },
  { id: 'italic', group: 'entry', keys: ['Mod+I'] },
  { id: 'rich-text-toolbar', group: 'entry', keys: ['Alt+F10'] },
  { id: 'add-note', group: 'entry', keys: ['Mod+Alt+M'] },

  // Block editor
  { id: 'module-picker-move', group: 'block', keys: ['ArrowUp', 'ArrowDown'] },
  { id: 'module-picker-insert', group: 'block', keys: ['Enter'] },
]

export function find(id, shortcuts = SHORTCUTS) {
  return shortcuts.find(shortcut => shortcut.id === id)
}

// `Mod+Shift+S` → { mod: true, shift: true, alt: false, ctrl: false, key: 's' }
export function parseChord(chord) {
  const parts = chord.split('+')
  const key = parts.pop()
  const has = name => parts.includes(name)
  return { mod: has('Mod'), shift: has('Shift'), alt: has('Alt'), ctrl: has('Ctrl'), key: key.length === 1 ? key.toLowerCase() : key }
}

// A shortcut without ⌘, Ctrl or Alt: a letter or symbol typed on its own.
// These are the ones a text field must keep, and the ones the user can turn off.
export function isCharacterShortcut(shortcut) {
  if (shortcut.sequence) return true
  return (shortcut.keys || []).some(chord => {
    const { mod, alt, ctrl, key } = parseChord(chord)
    return !mod && !alt && !ctrl && key.length === 1
  })
}

function eventKey(event) {
  const key = event.key || ''
  return key.length === 1 ? key.toLowerCase() : key
}

// Whether `event` is the chord. ⌘ or Ctrl both count as `Mod`, on any
// platform, as the save and palette shortcuts always have. With Alt, a Mac
// types another character (⌥M is µ), so the letter is read from `code`.
export function matchesChord(chord, event) {
  const want = typeof chord === 'string' ? parseChord(chord) : chord
  const mod = !!(event.metaKey || event.ctrlKey)
  if (want.mod !== mod) return false
  if (!want.mod && want.ctrl !== !!event.ctrlKey) return false
  if (want.alt !== !!event.altKey) return false

  // `?` is typed with Shift on most layouts, and other symbols vary too:
  // a symbol matches on the character alone.
  const symbol = want.key.length === 1 && !/[a-z0-9]/.test(want.key)
  if (!symbol && want.shift !== !!event.shiftKey) return false
  if (eventKey(event) === want.key) return true
  return want.alt && /^[a-z]$/.test(want.key) && event.code === `Key${want.key.toUpperCase()}`
}

// Whether `event` is one of the shortcut's chords (not its sequence).
export function matches(idOrShortcut, event, shortcuts = SHORTCUTS) {
  const shortcut = typeof idOrShortcut === 'string' ? find(idOrShortcut, shortcuts) : idOrShortcut
  return !!shortcut?.keys?.some(chord => matchesChord(chord, event))
}

/**
 * Follows the keys pressed for sequences such as `g` then `d`. `feed` takes
 * each keydown (already past the text-field and dialog checks) and answers:
 *
 * - `{ id }`: a shortcut is complete;
 * - `{ pending: true }`: the first key of a sequence, waiting for the next;
 * - `null`: nothing.
 *
 * A key that completes nothing ends the wait. A sequence's second key wins
 * over a single-key shortcut on the same key: `g` then `c` is Configuration,
 * not a new entry.
 */
export function createSequencer({ shortcuts = SHORTCUTS, timeout = SEQUENCE_TIMEOUT, now = () => Date.now() } = {}) {
  const sequences = shortcuts.filter(shortcut => shortcut.sequence && shortcut.dispatch)
  const singles = shortcuts.filter(
    shortcut => shortcut.dispatch && shortcut.keys && isCharacterShortcut(shortcut)
  )
  let pending = null
  const waiting = () => (pending && now() - pending.at <= timeout ? pending.key : null)

  return {
    get pending() {
      return waiting()
    },

    reset() {
      pending = null
    },

    feed(event) {
      if (event.metaKey || event.ctrlKey || event.altKey) {
        pending = null
        return null
      }
      const key = eventKey(event)
      // Shift alone, before the `?`, is not a key of its own
      if (['Shift', 'CapsLock', 'Dead'].includes(key)) return null

      const first = waiting()
      pending = null

      if (first) {
        const done = sequences.find(shortcut => shortcut.sequence[0] === first && shortcut.sequence[1] === key)
        if (done) return { id: done.id }
      }

      if (!event.shiftKey && sequences.some(shortcut => shortcut.sequence[0] === key)) {
        pending = { key, at: now() }
        return { pending: true }
      }

      const single = singles.find(shortcut => shortcut.keys.some(chord => matchesChord(chord, event)))
      return single ? { id: single.id } : null
    },
  }
}

// The keys, as the sheet shows them: a list of alternatives, each a list of
// keys, with `then` between the keys of a sequence. `mac` picks ⌘ ⇧ ⌥ over
// Ctrl, Shift and Alt.
const MAC_NAMES = { Mod: '⌘', Shift: '⇧', Alt: '⌥', Ctrl: '⌃' }
const OTHER_NAMES = { Mod: 'Ctrl', Shift: 'Shift', Alt: 'Alt', Ctrl: 'Ctrl' }
const KEY_NAMES = { ArrowUp: '↑', ArrowDown: '↓', ArrowLeft: '←', ArrowRight: '→', Enter: '↵', Escape: 'Esc' }

export function keyLabel(key) {
  if (KEY_NAMES[key]) return KEY_NAMES[key]
  return key.length === 1 ? key.toUpperCase() : key
}

export function displayKeys(shortcut, mac) {
  if (shortcut.sequence) return [shortcut.sequence.map(keyLabel)]
  const names = mac ? MAC_NAMES : OTHER_NAMES
  return shortcut.keys.map(chord => {
    const parts = chord.split('+')
    const key = parts.pop()
    // A Mac writes ⌃⌥⇧⌘ in that order
    const order = mac ? ['Ctrl', 'Alt', 'Shift', 'Mod'] : ['Mod', 'Ctrl', 'Alt', 'Shift']
    return [...order.filter(name => parts.includes(name)).map(name => names[name]), keyLabel(key)]
  })
}

export function isMacPlatform(platform = '') {
  return /mac|iphone|ipad/i.test(platform)
}

// Typing goes to these, so a plain key there is text, never a shortcut.
// Buttons, checkboxes and the like do not take text.
const TEXT_INPUT_TYPES = /^(text|search|email|url|tel|password|number|date|datetime-local|month|week|time)$/i

export function isTextTarget(el) {
  if (!el || typeof el.closest !== 'function') return false
  const tag = (el.tagName || '').toLowerCase()
  if (tag === 'input') return TEXT_INPUT_TYPES.test(el.type || 'text')
  if (tag === 'textarea' || tag === 'select') return true
  if (el.isContentEditable) return true
  return !!el.closest('[contenteditable]:not([contenteditable="false"]), .cm-editor, .ProseMirror')
}

// Focus inside a dialog: an open <dialog>, a `Content.modal`, a drawer or any
// `role="dialog"`. The dialog has the keys then, apart from what it gives back.
export const DIALOG_SELECTOR = 'dialog[open], [role="dialog"], [role="alertdialog"], [aria-modal="true"], .modal, .media-workspace-drawer'

// The first of `elements` a click could reach: a shortcut that runs an
// element's command skips one that is disabled or inside an inert part of
// the page (an entry's tools while its blocks load).
export function firstUsable(elements) {
  return Array.from(elements || []).find(
    el => !(typeof el.matches === 'function' && el.matches(':disabled')) &&
      !(typeof el.closest === 'function' && el.closest('[inert]'))
  ) || null
}

export function inDialog(el) {
  return !!(el && typeof el.closest === 'function' && el.closest(DIALOG_SELECTOR))
}
