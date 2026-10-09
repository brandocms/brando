/**
 * The admin's keyboard shortcuts at run time: one capturing `keydown` on the
 * window for the modified ones (⌘K works in a text field and over a dialog),
 * and one in the bubbling phase for the single keys and sequences (`?`,
 * `g` then `d`), so a widget that takes a letter for itself can still
 * `preventDefault()` it first. What there is lives in `./registry.js`.
 *
 * A hook that owns a shortcut binds its handler while it is mounted:
 *
 *   this.unbindFilter = bindShortcut('filter', () => input.focus())
 *
 * A handler that returns `false` did nothing, and the key goes on as typed.
 *
 * Single keys and sequences never fire while typing (inputs, textareas,
 * contenteditable, CodeMirror, TipTap) or while a dialog has the focus, and
 * not at all when the user has turned them off on the shortcut sheet: that is
 * kept in this browser, per user (`characterKeysEnabled`).
 */
import {
  SHORTCUTS,
  createSequencer,
  firstUsable,
  isCharacterShortcut,
  isTextTarget,
  inDialog,
  matches,
} from './registry'

const handlers = new Map()
const sequencer = createSequencer()
let installed = false

export function bindShortcut(id, handler) {
  handlers.set(id, handler)
  return () => {
    if (handlers.get(id) === handler) handlers.delete(id)
  }
}

function userId() {
  return document.querySelector('meta[name="user_id"]')?.getAttribute('content') || 'anonymous'
}

function storageKey() {
  return `brando:shortcuts:character-keys:${userId()}`
}

export function characterKeysEnabled() {
  try {
    return localStorage.getItem(storageKey()) !== 'off'
  } catch {
    return true
  }
}

export function setCharacterKeysEnabled(enabled) {
  try {
    if (enabled) localStorage.removeItem(storageKey())
    else localStorage.setItem(storageKey(), 'off')
  } catch {
    // Private mode or a full store: the choice lasts for this page only.
  }
  sequencer.reset()
}

// A modal <dialog> makes the rest of the page inert, wherever the focus is.
function modalDialogOpen() {
  try {
    return !!document.querySelector('dialog:modal')
  } catch {
    return false
  }
}

// Where a "go to" shortcut leads for this user: the sidebar is their menu, so
// a screen they may not open has no link there, and no shortcut either.
export function destination(shortcut) {
  if (shortcut.menu) {
    const link = document.querySelector(`#nav [data-menu-key="${shortcut.menu}"] dd a[href]`)
    return link ? link.getAttribute('href') : null
  }
  if (shortcut.always) return shortcut.href
  return document.querySelector(`#nav a[href="${shortcut.href}"]`) ? shortcut.href : null
}

function navigate(app, href) {
  if (!href) return false
  if (app?.liveSocket?.isConnected?.()) app.liveSocket.js().navigate(href)
  else window.location.assign(href)
  return true
}

function createUrl() {
  return document.querySelector('#brando-main[data-create-url]')?.dataset.createUrl || null
}

function previewToggle() {
  return firstUsable(document.querySelectorAll('[data-toggle-preview]'))
}

// Whether the shortcut can do anything for this user on this page. The sheet
// leaves out the "go to" rows that lead nowhere.
export function available(shortcut) {
  if (shortcut.id.startsWith('go-')) return !!destination(shortcut)
  return true
}

function builtIn(app, id) {
  const shortcut = SHORTCUTS.find(s => s.id === id)
  if (id.startsWith('go-')) return () => navigate(app, destination(shortcut))
  if (id === 'new-entry') return () => navigate(app, createUrl())
  if (id === 'preview') {
    return () => {
      const toggle = previewToggle()
      if (!toggle || !app?.liveSocket) return false
      app.liveSocket.execJS(toggle, toggle.dataset.togglePreview)
      return true
    }
  }
  return null
}

function run(app, id, event) {
  const handler = handlers.get(id) || builtIn(app, id)
  if (!handler) return false
  return handler(event) !== false
}

const chords = SHORTCUTS.filter(shortcut => shortcut.dispatch && !isCharacterShortcut(shortcut))

function target(event) {
  return (event.composedPath && event.composedPath()[0]) || event.target
}

export default function installShortcuts(app) {
  if (installed) return
  installed = true

  window.addEventListener(
    'keydown',
    event => {
      if (event.isComposing) return
      const shortcut = chords.find(candidate => matches(candidate, event))
      if (!shortcut) return
      const el = target(event)
      if (!shortcut.inText && (isTextTarget(el) || isTextTarget(document.activeElement))) return
      if (!shortcut.inModal && (inDialog(document.activeElement) || modalDialogOpen())) return
      if (run(app, shortcut.id, event)) {
        event.preventDefault()
        event.stopPropagation()
      }
    },
    true
  )

  window.addEventListener('keydown', event => {
    if (event.defaultPrevented || event.isComposing || event.repeat) return
    // Admin screens only: not the login page or frontend edit mode
    if (!document.getElementById('brando-main')) return
    const el = target(event)
    if (
      isTextTarget(el) ||
      isTextTarget(document.activeElement) ||
      inDialog(el) ||
      inDialog(document.activeElement) ||
      modalDialogOpen() ||
      !characterKeysEnabled()
    ) {
      sequencer.reset()
      return
    }
    const result = sequencer.feed(event)
    if (result?.id && run(app, result.id, event)) event.preventDefault()
  })
}
