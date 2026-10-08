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

export default (hooks) => {
  let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute('content')
  let liveSocket = new LiveSocket('/live', Socket, {
    hooks: hooks,
    params: { _csrf_token: csrfToken },
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
