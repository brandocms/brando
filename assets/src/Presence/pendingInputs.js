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
// that takes its place, and sent from there; the focus goes with it. Rich
// text is not carried.
//
// Dependency free, so `test/javascript/pending_inputs.test.mjs` runs it in
// Node.

export const PENDING_INPUT_MS = 2000
const TYPED_VALUES = 50

export const blockInput = el =>
  (el?.tagName === 'INPUT' || el?.tagName === 'TEXTAREA') && !!el.closest('[data-block-uid]')

// An input the editor types into, which a carried value can be put back in.
// A rich text field's hidden input is not: its editor shows what it holds.
const textInput = el => !!el.name && !['hidden', 'checkbox', 'radio', 'file'].includes(el.type)

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
  // block uid → { at, inputs: [{ name, value, focus }] }, from a block that went
  const carried = new Map()
  // The element with the focus, as focus events last said: a focused input
  // taken out of the page sends no focusout, so it stays named here.
  let focusedEl = null

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
  // place.
  const went = (blockEl, uid) => {
    if (!uid) return
    const inputs = Array.from(blockEl.querySelectorAll?.('input, textarea') || [])
      .filter(input => textInput(input) && now() - (lastInput.get(input) || -Infinity) < PENDING_INPUT_MS)
      .map(input => ({ name: input.name, value: input.value, focus: input === focusedEl }))
    if (inputs.length) carried.set(uid, { at: now(), inputs })
  }

  // Block `uid` mounted: what its last element held is put back where the
  // render shows something else, and sent (an `input` event, as typing sends
  // it).
  const came = (blockEl, uid) => {
    const carry = uid && carried.get(uid)
    if (!carry) return
    carried.delete(uid)
    if (now() - carry.at >= PENDING_INPUT_MS) return

    carry.inputs.forEach(({ name, value, focus }) => {
      const input = Array.from(blockEl.querySelectorAll?.('input, textarea') || []).find(el => el.name === name)
      if (!input) return
      if (input.value !== value) {
        input.value = value
        input.dispatchEvent(new Event('input', { bubbles: true }))
      }
      if (focus && !activeInDocument()) {
        input.focus()
        input.setSelectionRange?.(value.length, value.length)
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

  return { typed, patching, left, went, came, focused }
}
