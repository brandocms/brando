import { LiveSocket } from 'phoenix_live_view'
import { Socket } from 'phoenix'

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

// Block inputs while another editor's changes arrive (field presence, #2992).
//
// LiveView leaves the focused input's value alone when it patches; a rich
// text editor's hidden input is not focused (its editor is), so it is kept
// here while the editor is in use and was typed into in the last moments —
// a patch must not put back what the server rendered before the keystroke.
//
// Either way the server's value is noted. When the editor leaves the field
// and has not typed since that value arrived, the input takes it: the other
// editor typed last, and last arrival wins.
const PENDING_INPUT_MS = 2000
const lastInput = new WeakMap()
const serverValue = new WeakMap()

const blockInput = el => (el?.tagName === 'INPUT' || el?.tagName === 'TEXTAREA') && el.closest('[data-block-uid]')

document.addEventListener(
  'input',
  ({ target }) => {
    if (blockInput(target)) {
      lastInput.set(target, Date.now())
      serverValue.delete(target)
    }
  },
  true
)

// The rich text editor this hidden input belongs to has the focus.
const editorInUse = input =>
  input.classList.contains('tiptap-text') &&
  !!input.closest('[phx-hook="Brando.TipTap"]')?.contains(document.activeElement)

const keepPendingValue = (from, to) => {
  if (from.value === to.value || !blockInput(from)) return
  const focused = from === document.activeElement
  const richText = !focused && editorInUse(from)
  if (!focused && !richText) return

  serverValue.set(from, { value: to.value, at: Date.now() })

  const typedAt = lastInput.get(from)
  if (richText && typedAt && Date.now() - typedAt < PENDING_INPUT_MS) {
    to.value = from.value
    to.setAttribute('value', from.value)
  }
}

const takeServerValues = widget => {
  const inputs = blockInput(widget) ? [widget] : Array.from(widget.querySelectorAll?.('input, textarea') || [])
  inputs.forEach(input => {
    const noted = serverValue.get(input)
    if (!noted || input === document.activeElement) return
    serverValue.delete(input)
    if ((lastInput.get(input) || 0) > noted.at || input.value === noted.value) return
    input.value = noted.value
    input.closest('[phx-hook="Brando.TipTap"]')?.dispatchEvent(new CustomEvent('brando:tiptap:sync'))
  })
}

document.addEventListener(
  'focusout',
  ({ target }) => {
    // after LiveView has flushed the field's own debounced change
    if (target?.closest?.('[data-block-uid]')) {
      const widget = target.closest('[phx-hook]') || target
      setTimeout(() => {
        if (!widget.contains(document.activeElement)) takeServerValues(widget)
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
        if (from.tagName === 'INPUT' || from.tagName === 'TEXTAREA') keepPendingValue(from, to)
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
