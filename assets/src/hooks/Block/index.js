import autosize from 'autosize'

export default (app) => ({
  mounted() {
    this.$wrapper = this.el.closest('[data-block-index]')
    this.$baseBlock = this.el.closest('.base-block')
    this.index = parseInt(this.$wrapper.dataset.blockIndex)
    this.autosized = this.el.querySelectorAll('[data-autosize]')
    this.autosizeElements()
  },

  autosizeElements() {
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    this.autosizeElements()
  }
})