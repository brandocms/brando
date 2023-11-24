import { Dom } from '@brandocms/jupiter'
import Flatpickr from 'flatpickr'
import { Norwegian } from 'flatpickr/dist/l10n/no.js'

const LOCALES = {
  no: Norwegian
}

export default app => ({
  mounted() {
    this.locale = this.el.dataset.locale
    this.initialize()
  },

  destroyed() {
    this.flatpickrInstance?.destroy()
  },

  initialize() {
    let opts = {
      enableTime: false,
      altInput: true,
      altFormat: 'd/m/y',
      dateFormat: 'Y-m-d',
      allowInput: true
    }

    if (this.locale !== 'en') {
      opts = { ...opts, locale: LOCALES[this.locale] }
    }

    this.$btnClear = Dom.find(this.el, 'button.clear-datetime')
    this.$targetEl = Dom.find(this.el, '.flatpickr')
    this.flatpickrInstance = Flatpickr(this.$targetEl, opts)

    this.$btnClear.addEventListener('click', () => {
      this.flatpickrInstance.clear()
    })
  }
})
