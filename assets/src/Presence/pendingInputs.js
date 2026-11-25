// Block inputs while another editor's changes arrive (field presence, #2992),
// and an entry form's rich text field while its typing is on its way.
//
// LiveView leaves the focused input's value alone when it patches; a rich
// text editor's hidden input is not focused (its editor is), so it is kept
// here while the editor is in use and was typed into in the last moments —
// a patch must not put back what the server rendered before the keystroke.
//
// A value the server sends that this editor never typed is another
// editor's: it is noted, and when this editor leaves the field without
// typing again, the input takes it (last arrival wins). The server's answer
// to one of this editor's own earlier keystrokes is not noted, and a value
// equal to the input's clears the note: the server holds what is shown.
//
// A block that mounts again (moved to another row, by this editor or
// another) is a new element: what was typed into the old one in the last
// moments may still be waiting on the input's debounce, which LiveView drops
// with the element. It is carried to the input of the same name in the block
// that takes its place (never one of the blocks inside it, whose inputs have
// the same names), and sent from there; the focus goes with it. It is not
// put back over a value the server took from elsewhere since: one noted
// while this editor was in the field (the move leaves the field, which
// takes it), or one the new block renders that is neither what the server
// last had nor one this editor typed.
//
// Dependency free, so `test/javascript/pending_inputs.test.mjs` runs it in
// Node.

export const PENDING_INPUT_MS = 2000
// An element taken out of the page lost the focus in the same patch
const REMOVAL_BLUR_MS = 100
const TYPED_VALUES = 50

export const blockInput = el =>
  (el?.tagName === 'INPUT' || el?.tagName === 'TEXTAREA') && !!el.closest('[data-block-uid]')

// An input the editor types into, which a carried value can be put back in:
// a rich text field's hidden input too, whose editor shows what it holds.
const textInput = el =>
  !!el.name && (el.type === 'hidden' ? !!el.classList?.contains('tiptap-text') : !['checkbox', 'radio', 'file'].includes(el.type))

// The input types a caret can be set in (others throw)
const SELECTABLE = ['text', 'textarea', 'search', 'url', 'tel', 'password']

const ownInputs = blockEl =>
  Array.from(blockEl.querySelectorAll?.('input, textarea') || []).filter(input => input.closest('[phx-hook="Brando.Block"]') === blockEl)

// The rich text editor this hidden input belongs to has the focus.
const editorInUse = (input, active) =>
  input.classList.contains('tiptap-text') && !!input.closest('[phx-hook="Brando.TipTap"]')?.contains(active)

// A rich text field of an entry form (not a block's): an entry field, a
// subform row, a var, a caption.
const entryRichText = el =>
  el?.tagName === 'INPUT' &&
  !!el.classList?.contains('tiptap-text') &&
  el.closest('[phx-hook="Brando.TipTap"]')?.dataset?.tiptapType === 'rich_text' &&
  !el.closest('[data-block-uid]')

export default function pendingInputs({ now = () => Date.now(), activeElement = () => document.activeElement } = {}) {
  const lastInput = new WeakMap()
  const typedValues = new WeakMap()
  const serverValue = new WeakMap()
  // What the server last rendered into a block's input
  const rendered = new WeakMap()
  // block uid → { at, inputs: [{ name, value, server, typed, focus }] }, from a block that went
  const carried = new Map()
  const forget = uid => {
    clearTimeout(carried.get(uid)?.timer)
    carried.delete(uid)
  }
  const clear = () => {
    for (const uid of carried.keys()) forget(uid)
    focusedEl = null
    blurred = { el: null, at: -Infinity }
  }
  // The element with the focus, as focus events last said, and the one
  // that last lost it: a browser takes the focus from an element as it
  // takes the element out of the page, or does not, and sends no focusout.
  let focusedEl = null
  let blurred = { el: null, at: -Infinity }

  // This editor typed into `input`.
  const typed = input => {
    if (!blockInput(input) && !entryRichText(input)) return
    lastInput.set(input, now())
    serverValue.delete(input)
    const values = typedValues.get(input) || []
    values.push(input.value)
    if (values.length > TYPED_VALUES) values.shift()
    typedValues.set(input, values)
  }

  // LiveView is about to patch `from` with `to` (morphdom's onBeforeElUpdated).
  const patching = (from, to) => {
    const active = activeElement()

    // While its editor is in use, a value the server rendered before the
    // last keystrokes (one this editor typed since the server last agreed,
    // or any in the moments after typing) would replace text still waiting
    // on the input's debounce, which would then send the older value. Other
    // values are the server's (a handed-over edit), and are taken.
    if (entryRichText(from)) {
      if (from.value === to.value) {
        typedValues.delete(from)
        return
      }
      const own = (typedValues.get(from) || []).includes(to.value)
      const typedAt = lastInput.get(from)
      if (editorInUse(from, active) && (own || (typedAt && now() - typedAt < PENDING_INPUT_MS))) {
        to.value = from.value
        to.setAttribute('value', from.value)
      }
      return
    }

    if (!blockInput(from)) return
    rendered.set(from, to.value)
    const focused = from === active
    const richText = !focused && editorInUse(from, active)
    if (!focused && !richText) return

    if (from.value === to.value) {
      serverValue.delete(from)
      return
    }

    const own = (typedValues.get(from) || []).includes(to.value)
    if (!own) serverValue.set(from, { value: to.value, at: now() })

    const typedAt = lastInput.get(from)
    if (richText && (own || (typedAt && now() - typedAt < PENDING_INPUT_MS))) {
      to.value = from.value
      to.setAttribute('value', from.value)
    }
  }

  // The editor left `widget` (an input, or the hook element around one):
  // its inputs take another editor's value noted while it was there.
  const left = widget => {
    const inputs = blockInput(widget) ? [widget] : Array.from(widget.querySelectorAll?.('input, textarea') || [])
    inputs.forEach(input => {
      if (input === activeElement()) return
      typedValues.delete(input)
      const noted = serverValue.get(input)
      if (!noted) return
      serverValue.delete(input)
      if ((lastInput.get(input) || 0) > noted.at || input.value === noted.value) return
      input.value = noted.value
      input.closest('[phx-hook="Brando.TipTap"]')?.dispatchEvent(new CustomEvent('brando:tiptap:sync'))
    })
  }

  // The element of block `uid` went (its hook was destroyed): the inputs
  // typed into in the last moments are kept for the block that takes its
  // place, with what the server had in them (the value attribute a focused
  // input keeps from before its focus, or a later render; a hidden input's
  // attribute is its value, so only a render tells) and what this editor
  // typed.
  const went = (blockEl, uid) => {
    if (!uid) return
    const inputs = ownInputs(blockEl)
      .filter(input => textInput(input) && now() - (lastInput.get(input) || -Infinity) < PENDING_INPUT_MS)
      .map(input => ({
        name: input.name,
        value: serverValue.get(input)?.value ?? input.value,
        server: rendered.has(input) ? rendered.get(input) : input.type === 'hidden' ? undefined : input.defaultValue,
        typed: typedValues.get(input) || [],
        focus: input === focusedEl || (input === blurred.el && now() - blurred.at < REMOVAL_BLUR_MS),
      }))
    if (inputs.length) {
      forget(uid)
      const timer = setTimeout(() => carried.delete(uid), PENDING_INPUT_MS)
      carried.set(uid, { at: now(), inputs, timer })
    }
  }

  // Block `uid` mounted: what its last element held is put back where the
  // render shows what the server had before it, and sent (an `input` event,
  // as typing sends it).
  const came = (blockEl, uid) => {
    const carry = uid && carried.get(uid)
    if (!carry) return
    forget(uid)
    if (now() - carry.at >= PENDING_INPUT_MS) return

    const inputs = ownInputs(blockEl)
    carry.inputs.forEach(({ name, value, server, typed, focus }) => {
      const input = inputs.find(el => el.name === name)
      if (!input) return
      if (input.value !== value && (server === undefined || input.value === server || typed.includes(input.value))) {
        input.value = value
        input.dispatchEvent(new Event('input', { bubbles: true }))
        input.closest('[phx-hook="Brando.TipTap"]')?.dispatchEvent(new CustomEvent('brando:tiptap:sync'))
      }
      if (focus && !activeInDocument()) {
        input.focus()
        if (SELECTABLE.includes(input.type)) input.setSelectionRange(input.value.length, input.value.length)
      }
    })
  }

  // Something on the page has the focus
  const activeInDocument = () => {
    const active = activeElement()
    return !!active && active.tagName !== 'BODY'
  }

  const focused = el => {
    focusedEl = el
  }

  const unfocused = el => {
    focusedEl = null
    blurred = { el, at: now() }
  }

  return { typed, patching, left, went, came, focused, unfocused, clear }
}
