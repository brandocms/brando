import autosize from 'autosize'

export default app => ({
  mounted() {
    console.log('=> mounted autosize — ignoring.')
    // this.autosizeElements()
  },

  autosizeElements() {
    this.autosized = this.el.querySelectorAll('[data-autosize]')
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    // this.autosizeElements()
  }
})
