/**
 * TransformerFields — sends a transformer entry's field edits to the
 * transformer.
 *
 * An entry's inputs (in the grid's edit modal or an expanded list card) render
 * inside the main form, so left alone their changes go to the form's
 * `validate`, which knows nothing about `transformer_item[...]`, and the edit
 * is lost when the form is saved. This catches `input` and `change` events on
 * their way up, stops them before LiveView's form binding sees them, and
 * pushes `update_field` to the transformer instead. Text is debounced; radios,
 * checkboxes and selects go at once.
 */
const FIELD = /^transformer_item\[([a-z0-9_]+)\]$/
const TYPED = /^(text|search|url|email|number|tel)$/
const DEBOUNCE = 300

export default () => ({
  mounted() {
    this.timers = {}
    this.pending = {}

    this.onEvent = (e) => {
      const input = e.target
      const match = input.name && input.name.match(FIELD)
      if (!match) return

      e.stopPropagation()
      if (input.type === 'radio' && !input.checked) return

      const field = match[1]
      const value = input.type === 'checkbox' ? input.checked : input.value
      const push = () =>
        this.pushEventTo(this.el.dataset.target, 'update_field', {
          dom_id: this.el.dataset.domId,
          field,
          value
        })

      clearTimeout(this.timers[field])
      delete this.pending[field]
      const typing = e.type === 'input' && (input.tagName === 'TEXTAREA' || TYPED.test(input.type))
      if (typing) {
        this.pending[field] = push
        this.timers[field] = setTimeout(() => {
          delete this.pending[field]
          push()
        }, DEBOUNCE)
      } else {
        push()
      }
    }

    // A save asks for what is held back (`Form/pendingChange.js`), so the
    // text typed last reaches the transformer before the save collects it.
    this.onFlush = () => {
      Object.entries(this.pending).forEach(([field, push]) => {
        clearTimeout(this.timers[field])
        delete this.pending[field]
        push()
      })
    }
    document.addEventListener('brando:flush', this.onFlush)

    this.el.addEventListener('input', this.onEvent)
    this.el.addEventListener('change', this.onEvent)
  },

  destroyed() {
    document.removeEventListener('brando:flush', this.onFlush)
    Object.values(this.timers).forEach(clearTimeout)
    this.el.removeEventListener('input', this.onEvent)
    this.el.removeEventListener('change', this.onEvent)
  }
})
