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
    this.pushEventTo(this.el, 'focus', { field: fName })
  },

  handleBlur() {
    this.pushEventTo(this.el, 'blur', {})
  },

  destroyed() {
    if (this.field) {
      this.field.removeEventListener('focus', this._handleFocus)
      this.field.removeEventListener('blur', this._handleBlur)
    }
  },
})
