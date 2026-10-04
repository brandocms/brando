import { Dom } from '@brandocms/jupiter'
import Flatpickr from 'flatpickr'
import { Norwegian } from 'flatpickr/dist/l10n/no.js'

const LOCALES = {
  no: Norwegian
}

export default app => ({
  mounted() {
    this.locale = this.el.dataset.locale
    this.serverValue = this.el.dataset.value
    this.initialize()
  },

  updated() {
    const value = this.el.dataset.value
    if (value === this.serverValue) return

    this.serverValue = value
    // The named input lives inside the ignored Flatpickr subtree. Applying a
    // server value must update both controls without emitting another edit.
    if (value) {
      this.flatpickrInstance.setDate(value, false)
    } else {
      this.flatpickrInstance.clear(false)
    }
  },

  destroyed() {
    this.$btnClear?.removeEventListener('click', this.clearDate)
    this.flatpickrInstance?.destroy()
  },

  initialize() {
    let opts = {
      enableTime: true,
      minuteIncrement: 15,
      time_24hr: true,
      altInput: true,
      // Compact so two fit side by side, matching the date picker's d/m/y; the
      // short weekday stays, it is what shows a date fell on the wrong day.
      // A caller can still ask for its own (`alt_format:` on the input)
      altFormat: this.el.dataset.altFormat || 'D d/m/y @ H:i',
      dateFormat: 'Z',
      allowInput: true
    }

    if (this.locale !== 'en') {
      opts = { ...opts, locale: LOCALES[this.locale] }
    }

    this.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
    this.$timezoneEl = Dom.find(this.el, '.timezone [data-timezone]')
    this.$btnClear = Dom.find(this.el, 'button.clear-datetime')
    this.$targetEl = Dom.find(this.el, '.flatpickr')
    this.flatpickrInstance = Flatpickr(this.$targetEl, opts)

    this.$timezoneEl.innerHTML = this.timezone

    this.clearDate = () => this.flatpickrInstance.clear()
    this.$btnClear.addEventListener('click', this.clearDate)
  }
})
