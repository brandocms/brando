export default (app) => ({
  mounted() {
    this.field = this.el.querySelector('[data-watch-focus]')
    console.log('watchFocus', this.field)
    if (this.field) {
      this.field.addEventListener('focus', this.handleFocus.bind(this))
    }
  },

  handleFocus() {
    console.log('==> Field focus')
    const fName = this.field.getAttribute('name')
    this.pushEventTo(this.el, 'focus', { field: fName })
  },
})
