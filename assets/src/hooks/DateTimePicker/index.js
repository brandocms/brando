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
      enableTime: true,
      minuteIncrement: 15,
      time_24hr: true,
      altInput: true,
      altFormat: 'l j F, Y @ H:i',
      dateFormat: 'Z',
      allowInput: true
    }

    if (this.locale !== 'en') {
      opts = { ...opts, locale: LOCALES[this.locale] }
    }

    this.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    this.$timezoneEl = Dom.find(this.el, '.timezone span')
    this.$btnClear = Dom.find(this.el, 'button.clear-datetime')
    this.$targetEl = Dom.find(this.el, '.flatpickr')
    this.flatpickrInstance = Flatpickr(this.$targetEl, opts)

    this.$timezoneEl.innerHTML = this.timezone

    this.$btnClear.addEventListener('click', () => {
      this.flatpickrInstance.clear()
    })
  }
})
