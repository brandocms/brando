import { flushInput } from '../Form/saveForm'

export default (app) => ({
  mounted() {
    this.field = this.el.querySelector('[data-watch-focus]')
    if (this.field) {
      this._handleFocus = this.handleFocus.bind(this)
      this._handleBlur = this.handleBlur.bind(this)
      this.field.addEventListener('focus', this._handleFocus)
      this.field.addEventListener('blur', this._handleBlur)
    }
  },

  // Field presence is tracked by the brando-form component, so focus and blur
  // go there, even from inputs inside a nested LiveComponent (subform, block,
  // etc.). Outside a form there is nothing to tell: the dialogs that render into
  // a portal on <body>, like a multi-select's "Create client", have no form
  // around them, and pushing to the LiveView instead crashed any view without
  // its own focus/blur handlers, discarding everything unsaved on the page.
  //
  // A field inside a block reports nothing here: the Block hook's field
  // presence covers it (`block_focused` with the field), and an entry-field
  // focus would lock the field and clear this editor's block presence.
  handleFocus() {
    if (this.el.closest('[data-block-uid]')) return
    const formEl = this.el.closest('.brando-form')
    if (formEl) {
      this.pushEventTo(formEl, 'focus', { field: this.field.getAttribute('name') })
    }
  },

  // A save flushes the focused input's pending change with a synthetic blur
  // (`Form/saveForm.js`); the editor is still in the field.
  //
  // The blur ships what the editor changed to the other editors, so the
  // last keystrokes have to reach the server first. LiveView sends a
  // pending debounced change on blur, from a listener it adds after this
  // one (on the first keystroke): flushing it here keeps the change ahead
  // of the blur.
  handleBlur(event) {
    if (event?.brandoFlush || this.el.closest('[data-block-uid]')) return
    const formEl = this.el.closest('.brando-form')
    if (formEl) {
      flushInput(this.field)
      this.pushEventTo(formEl, 'blur', {})
    }
  },

  destroyed() {
    if (this.field) {
      this.field.removeEventListener('focus', this._handleFocus)
      this.field.removeEventListener('blur', this._handleBlur)
    }
  },
})
