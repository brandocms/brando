import { Dom } from '@brandocms/jupiter'
import Flatpickr from 'flatpickr'
import { Norwegian } from 'flatpickr/dist/l10n/no.js'

const LOCALES = {
  no: Norwegian
}

export default (app) => ({
  mounted () {
    this.locale = this.el.dataset.locale
    this.initialize()
  },

  destroyed () {
    this.flatpickrInstance?.destroy()
  },

  initialize () {
    let opts = {      
      enableTime: true,
      minuteIncrement: 15,
      time_24hr: true,
      altInput: true,
      altFormat: 'l j F, Y @ H:i',
      dateFormat: 'Z',
      allowInput: true
    }

    this.revision = this.el.dataset.revision

    if (this.locale !== 'en') {
      opts = { ...opts, locale: LOCALES[this.locale] }
    }
    
    this.$targetEl = Dom.find(this.el, '.flatpickr')
    this.flatpickrInstance = Flatpickr(this.$targetEl, opts)

    const $button = this.el.nextElementSibling
    $button.addEventListener('click', e => {
      this.pushEventTo(this.el, 'schedule', {
        revision: this.revision,
        publish_at: this.$targetEl.value
      })
    })
  }
})