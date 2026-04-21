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

  handleFocus() {
    const fName = this.field.getAttribute('name')
    // Push to the brando-form component for field presence tracking,
    // even when the input is inside a nested LiveComponent (subform, block, etc.)
    const formEl = this.el.closest('.brando-form')
    if (formEl) {
      this.pushEventTo(formEl, 'focus', { field: fName })
    } else {
      this.pushEvent('focus', { field: fName })
    }
  },

  handleBlur() {
    const formEl = this.el.closest('.brando-form')
    if (formEl) {
      this.pushEventTo(formEl, 'blur', {})
    } else {
      this.pushEvent('blur', {})
    }
  },

  destroyed() {
    if (this.field) {
      this.field.removeEventListener('focus', this._handleFocus)
      this.field.removeEventListener('blur', this._handleBlur)
    }
  },
})
