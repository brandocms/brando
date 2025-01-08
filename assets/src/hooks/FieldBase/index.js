export default (app) => ({
  mounted() {
    this.field = this.el.querySelector('[data-watch-focus]')
    if (this.field) {
      this.field.addEventListener('focus', this.handleFocus.bind(this))
    }
  },

  handleFocus() {
    const fName = this.field.getAttribute('name')
    this.pushEventTo(this.el, 'focus', { field: fName })
  },
})
