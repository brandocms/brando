import { LiveSocket } from 'phoenix_live_view'
import { Socket } from 'phoenix'
import pendingInputs from './Presence/pendingInputs'

// Classes SortableJS owns at runtime, on elements that live inside the
// LiveView-rendered tree.
//
// A drag is client-only state: Sortable adds these after the server rendered
// the element, so they are absent from the markup LiveView diffs against. Any
// patch landing mid-drag — a debounced validate, a live-preview refresh, the
// position handshake — restores the server's `class` and takes them with it.
// The drop indicator snaps back to looking like an ordinary block while the
// drag is still running, and the drag itself keeps working, which is what makes
// it read as a rendering glitch rather than a lost class.
//
// Carrying them onto the incoming element is the documented way to hold
// client-owned classes across a patch, and it costs nothing when no drag is in
// progress: an element that does not have them stays untouched.
const SORTABLE_RUNTIME_CLASSES = [
  'is-sorting', // ghostClass — the drop indicator
  'sortable-chosen', // chosenClass — the picked-up element
  'sortable-ghost', // ghostClass default, for sortables that don't override it
  'drag-item', // dragClass
  'sortable-fallback', // fallbackClass
  'sortable-drag',
]

// Block inputs while another editor's changes arrive (field presence,
// #2992): see `Presence/pendingInputs.js`.
const pending = pendingInputs()

document.addEventListener('input', ({ target }) => pending.typed(target), true)

document.addEventListener(
  'focusout',
  ({ target }) => {
    // after LiveView has flushed the field's own debounced change
    if (target?.closest?.('[data-block-uid]')) {
      const widget = target.closest('[phx-hook]') || target
      setTimeout(() => {
        if (!widget.contains(document.activeElement)) pending.left(widget)
      }, 0)
    }
  },
  true
)

// This browser tab, across reloads and reconnects: an entry's form is
// edited in one tab per user, and the tab that edits keeps doing so when it
// reconnects (`BrandoAdmin.LiveView.Form.Tabs`).
//
// The id lives in sessionStorage, which a duplicated tab (and a window a
// script opens) copies. While a page is open its tab says so (`OPEN_KEY`),
// and says it no more as it goes (`pagehide`, which a reload passes through
// too): a page that finds the flag set is a copy of a tab still open, and
// takes an id of its own. Every join counts (`brando_tab_seq`), so that the
// server knows a tab's newest process from an old one it hasn't dropped yet.
const TAB_KEY = 'brando:tab'
const OPEN_KEY = 'brando:tab-open'
const SEQ_KEY = 'brando:tab-seq'

let tab
let seq = 0
try {
  tab = sessionStorage.getItem(TAB_KEY)
  if (!tab || sessionStorage.getItem(OPEN_KEY)) {
    tab = crypto.randomUUID()
    sessionStorage.setItem(TAB_KEY, tab)
    sessionStorage.removeItem(SEQ_KEY)
  }
  seq = parseInt(sessionStorage.getItem(SEQ_KEY) || '0', 10) || 0
  sessionStorage.setItem(OPEN_KEY, '1')
  window.addEventListener('pagehide', () => sessionStorage.removeItem(OPEN_KEY))
  window.addEventListener('pageshow', ({ persisted }) => {
    if (persisted) sessionStorage.setItem(OPEN_KEY, '1')
  })
} catch {
  tab = undefined
}

const nextSeq = () => {
  seq += 1
  try {
    sessionStorage.setItem(SEQ_KEY, String(seq))
  } catch {}
  return seq
}

// Close, on a form another of the editor's tabs edits. A browser closes only
// a tab a script opened; otherwise the button's navigation goes on.
window.addEventListener('brando:close-tab', () => window.close())

export default (hooks) => {
  let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute('content')
  let liveSocket = new LiveSocket('/live', Socket, {
    hooks: hooks,
    // A function, so every join (a reconnect, a live navigation) sends the
    // tab as it is now.
    params: () => ({ _csrf_token: csrfToken, brando_tab: tab, brando_tab_seq: nextSeq() }),
    timeout: 70000,
    dom: {
      onBeforeElUpdated(from, to) {
        for (const className of SORTABLE_RUNTIME_CLASSES) {
          if (from.classList.contains(className)) to.classList.add(className)
        }
        if (from.tagName === 'INPUT' || from.tagName === 'TEXTAREA') pending.patching(from, to)
      },
    },
    metadata: {
      click: (e, el) => {
        return {
          shiftKey: e.shiftKey,
          metaKey: e.metaKey,
          altKey: e.altKey,
          ctrlKey: e.ctrlKey,
        }
      },
      keydown: (e, el) => {
        return {
          key: e.key,
          metaKey: e.metaKey,
          shiftKey: e.shiftKey,
          repeat: e.repeat,
        }
      },
    },
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // expose liveSocket on window for web console debug logs and latency simulation:
  window.liveSocket = liveSocket
  return liveSocket
}
