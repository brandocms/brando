// Saving pushes the main form's fields as an event rather than submitting
// the form.
//
// A form submit makes LiveView blur the focused input and turn every input
// read-only until the server answers (`submitForm` → `blurActiveElement`,
// `disableForm`). A save takes two round trips (the block fields are
// collected first, then `b:submit` asks for the write), and every key typed
// in that time went nowhere. The edit session already keeps what is typed
// while a save runs, so the inputs can stay as they are.
//
// What a submit did besides is done here, and one thing it did not:
// * widgets that hold a change back in their own JS (the colour picker, a
//   transformer's text fields) are asked for it (`brando:flush`);
// * the focused input's pending debounced change is flushed, so the
//   save includes the last keystrokes (`flushFocused`);
// * every input is marked submitted, so the form's errors show for fields
//   the editor never touched (LiveView's `used_input?`);
// * `brando:save` is dispatched on the form, for the recovery copy's save
//   generation (`draftRecovery.js`).
//
// The push goes from an empty element beside the form (`data-save-source`),
// not from the element of the hook that calls it: a hook push locks its
// element until the reply, and a lock on the element around the block
// fields nests their own locks and drops blocks (see `draftRecovery.js`).

// LiveView's private DOM keys (`DOM.putPrivate`), as its submit sets them.
const PHX_PRIVATE = 'phxPrivate'
const PHX_HAS_SUBMITTED = 'phx-has-submitted'

const markSubmitted = el => {
  el[PHX_PRIVATE] = { ...(el[PHX_PRIVATE] || {}), [PHX_HAS_SUBMITTED]: true }
}

// The input that holds what the focused element edits: the element itself,
// or the hidden input or textarea of the widget around it (a rich text
// editor, a code editor) that LiveView sends.
const focusedInput = () => {
  const active = document.activeElement
  if (!active || active === document.body) return null
  if (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA') return active
  return active.closest?.('[phx-hook]')?.querySelector('input[phx-debounce], textarea[phx-debounce], .tiptap-text') || null
}

// LiveView sends a pending debounce on the input's blur event. It is
// dispatched without moving the focus, and marked, so the field presence
// handlers that also listen for blur (`FieldBase`) leave it alone.
export const flushFocused = () => {
  const input = focusedInput()
  if (!input) return
  const event = new Event('blur')
  event.brandoFlush = true
  input.dispatchEvent(event)
}

// The form's fields as LiveView would send them, files left out (uploads
// go on their own, `auto_upload`).
export const formPayload = form =>
  new URLSearchParams(Array.from(new FormData(form)).filter(([, value]) => typeof value === 'string')).toString()

const saveSource = form =>
  form.closest('[phx-hook="Brando.Form"], .brando-form')?.querySelector('[data-save-source]') || null

// A form that takes its fields as an event names it (`data-save-event`,
// the entry form). Any other form the save button belongs to is submitted.
// `token`: the `b:submit` this save answers. `stay`: save and continue
// editing (⌘S), sent with the save rather than in a push of its own.
export default function saveForm(hook, form, { token, stay } = {}) {
  const event = form.dataset.saveEvent
  if (!event) {
    form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    return
  }

  // widgets that hold a change back give it up now (`pendingChange.js`)
  document.dispatchEvent(new CustomEvent('brando:flush'))
  flushFocused()
  markSubmitted(form)
  Array.from(form.elements).forEach(markSubmitted)
  form.dispatchEvent(new CustomEvent('brando:save', { bubbles: true }))

  const value = { form: formPayload(form) }
  if (token !== undefined) value.token = token
  if (stay) value.stay = true
  const source = saveSource(form)
  if (source) hook.js().push(source, event, { value })
  else hook.pushEventTo(form, event, value)
}
