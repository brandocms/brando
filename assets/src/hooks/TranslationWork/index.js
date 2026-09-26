/**
 * Brando.TranslationWork — marks what a synchronized translation's open work
 * points at: blocks by uid (`data-blocks`) and fields by input name
 * (`data-fields`), both JSON arrays on the translation panel.
 *
 * It also locks what follows the source (`data-locks`, CSS selectors from the
 * server): the field wrapper of each `inert` input becomes inert, and each
 * `structure` subform is marked so its add, remove and reorder controls are
 * hidden. The server refuses those changes on save regardless.
 *
 * Marks are sticky attributes set through `this.js()`, so LiveView patches of
 * the blocks keep them; CSS draws them from `data-translation-work`. Blocks
 * mount after the panel when a pending version is loaded, so marking is
 * repeated shortly after mounting as well as on every update.
 */
export default () => ({
  mounted() {
    this.marked = []
    this.mark()
    this.timers = [300, 1000, 2500].map(delay => setTimeout(() => this.mark(), delay))
  },

  updated() {
    this.mark()
  },

  destroyed() {
    this.timers.forEach(clearTimeout)
    this.marked.forEach(el => el.isConnected && this.js().removeAttribute(el, 'data-translation-work'))
  },

  lock() {
    const { inert = [], structure = [] } = JSON.parse(this.el.dataset.locks || '{}')

    inert
      .flatMap(selector => [...document.querySelectorAll(selector)])
      .map(input => input.closest('.field-wrapper'))
      .filter(el => el && !el.hasAttribute('inert'))
      .forEach(el => {
        this.js().setAttribute(el, 'inert', '')
        this.js().setAttribute(el, 'data-source-locked', 'true')
      })

    structure
      .flatMap(selector => [...document.querySelectorAll(selector)])
      .map(el => el.closest('.subform') || el)
      .filter(el => !el.hasAttribute('data-source-structure'))
      .forEach(el => this.js().setAttribute(el, 'data-source-structure', 'true'))
  },

  mark() {
    this.lock()

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
