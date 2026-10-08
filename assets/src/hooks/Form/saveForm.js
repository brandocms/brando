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
// The focused input's pending debounced change is flushed first, so the
// save includes the last keystrokes: LiveView sends a pending debounce on
// the input's blur event, which is dispatched without moving the focus. A
// rich text editor has the focus in its editor, not its hidden input.

const focusedInput = () => {
  const active = document.activeElement
  if (!active || active === document.body) return null
  if (active.tagName === 'INPUT' || active.tagName === 'TEXTAREA') return active
  return active.closest?.('[phx-hook="Brando.TipTap"]')?.querySelector('.tiptap-text') || null
}

// The form's fields as LiveView would send them, files left out (uploads
// go on their own, `auto_upload`).
export const formPayload = form =>
  new URLSearchParams(Array.from(new FormData(form)).filter(([, value]) => typeof value === 'string')).toString()

export default function saveForm(hook, form) {
  focusedInput()?.dispatchEvent(new Event('blur'))
  hook.pushEventTo(form, 'save_form', { form: formPayload(form) })
}
