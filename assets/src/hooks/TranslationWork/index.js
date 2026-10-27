/**
 * Brando.TranslationWork — marks what a synchronized translation's open work
 * points at: blocks by uid (`data-blocks`) and fields by input name
 * (`data-fields`), both JSON arrays on the translation panel.
 *
 * It also locks what follows the source (`data-locks`, CSS selectors from the
 * server): the field of each `inert` input takes no edit, and each
 * `structure` subform is marked so its add, remove and reorder controls are
 * hidden. The server refuses those changes on save regardless.
 *
 * A locked field keeps its label and value readable, as a field locked by its
 * own `readonly:` does: text inputs and rich text become read-only, any other
 * control goes inert, and the label reads out the value the field renders as
 * text (`.field-value`, shown by `[data-source-locked]`).
 *
 * A block can also carry a note (`data-notes`, text by block uid), shown in
 * the block as `data-translation-note`, e.g. which linked entries it waits for.
 *
 * Marks are sticky attributes set through `this.js()`, so LiveView patches of
 * the blocks keep them; CSS draws them from `data-translation-work`. Blocks
 * mount after the panel when a pending version is loaded, so marking is
 * repeated shortly after mounting as well as on every update.
 */
export default () => ({
  mounted() {
    this.marked = []
    this.noted = []
    this.mark()
    this.timers = [300, 1000, 2500].map(delay => setTimeout(() => this.mark(), delay))
  },

  updated() {
    this.mark()
  },

  destroyed() {
    this.timers.forEach(clearTimeout)
    this.marked.forEach(el => el.isConnected && this.js().removeAttribute(el, 'data-translation-work'))
    this.noted.forEach(el => el.isConnected && this.js().removeAttribute(el, 'data-translation-note'))
  },

  note() {
    const notes = JSON.parse(this.el.dataset.notes || '{}')

    const noted = Object.entries(notes)
      .map(([uid, text]) => [document.querySelector(`[data-block-uid="${CSS.escape(uid)}"] > .block`), text])
      .filter(([el]) => el)

    this.noted
      .filter(el => el.isConnected && !noted.some(([target]) => target === el))
      .forEach(el => this.js().removeAttribute(el, 'data-translation-note'))

    noted
      .filter(([el, text]) => el.getAttribute('data-translation-note') !== text)
      .forEach(([el, text]) => this.js().setAttribute(el, 'data-translation-note', text))

    this.noted = noted.map(([el]) => el)
  },

  lock() {
    const { inert = [], structure = [] } = JSON.parse(this.el.dataset.locks || '{}')

    new Set(
      inert
        .flatMap(selector => [...document.querySelectorAll(selector)])
        .map(input => input.closest('.field-wrapper'))
        .filter(Boolean)
    ).forEach(el => this.lockField(el))

    structure
      .flatMap(selector => [...document.querySelectorAll(selector)])
      .map(el => el.closest('.subform') || el)
      .filter(el => !el.hasAttribute('data-source-structure'))
      .forEach(el => this.js().setAttribute(el, 'data-source-structure', 'true'))
  },

  // Repeated on every update, so a control LiveView puts back is locked again
  lockField(wrapper) {
    const set = (el, name, value = '') => el.getAttribute(name) !== value && this.js().setAttribute(el, name, value)
    set(wrapper, 'data-source-locked', 'true')

    const header = wrapper.querySelector(':scope > .label-wrapper > .field-wrapper-header')
    if (header) set(header, 'inert')

    const base = wrapper.querySelector(':scope > .field-base')
    if (!base) return set(wrapper, 'inert')

    // Rich text stops taking edits itself (the TipTap hook watches the
    // attribute); Translation.css hides its toolbar and reset button
    const richText = base.querySelector('[data-tiptap-readonly]')
    if (richText) return set(richText, 'data-tiptap-readonly', 'true')

    const controls = [...base.querySelectorAll('input:not([type="hidden"]), textarea, select, button, [contenteditable]')]
    const texts = controls.filter(el => el.matches('input.text, textarea.text'))
    const tabs = controls.filter(el => el.matches('[role="tab"]'))

    if (texts.length && texts.length + tabs.length === controls.length) {
      texts.forEach(el => set(el, 'readonly'))
    } else {
      set(base, 'inert')
      // Its click would reach the inert control
      const label = wrapper.querySelector(':scope > .label-wrapper > label')
      if (label?.hasAttribute('for')) this.js().removeAttribute(label, 'for')
    }
  },

  mark() {
    this.lock()
    this.note()

    const blocks = JSON.parse(this.el.dataset.blocks || '[]')
    const fields = JSON.parse(this.el.dataset.fields || '[]')

    const targets = [
      ...blocks.map(uid => document.querySelector(`[data-block-uid="${CSS.escape(uid)}"] > .block`)),
      ...fields.map(name => {
        const input = document.querySelector(`[name="${CSS.escape(name)}"], [name^="${CSS.escape(name)}["]`)
        return input && input.closest('.field-wrapper')
      }),
    ].filter(Boolean)

    this.marked
      .filter(el => el.isConnected && !targets.includes(el))
      .forEach(el => this.js().removeAttribute(el, 'data-translation-work'))

    targets
      .filter(el => !el.hasAttribute('data-translation-work'))
      .forEach(el => this.js().setAttribute(el, 'data-translation-work', 'true'))

    this.marked = targets
  },
})
