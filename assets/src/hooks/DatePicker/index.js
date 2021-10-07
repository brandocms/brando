import { Dom } from '@brandocms/jupiter'
import Flatpickr from 'flatpickr'

export default (app) => ({
  mounted() {
    this.initialize()
  },

  destroyed () {
    this.flatpickrInstance?.destroy()
  },

  initialize () {
    const opts = {
      enableTime: false,
      altInput: true,
      altFormat: 'l j F, Y',
      dateFormat: 'Z',
      allowInput: true
    }

    this.$btnClear = Dom.find(this.el, 'button.clear-datetime')
    this.$targetEl = Dom.find(this.el, '.flatpickr')
    this.flatpickrInstance = Flatpickr(this.$targetEl, opts)

    this.$btnClear.addEventListener('click', () => {
      this.flatpickrInstance.clear()
    })
  }
})