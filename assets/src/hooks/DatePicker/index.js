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
    // The named input lives inside the ignored Flatpickr subtree, so
    // LiveView never renames it. A subform row's inputs are named by
    // position, which changes when a row above it is removed; keep the name
    // current, or the next change sends this value as a stray row (#3157).
    const name = this.el.dataset.name
    if (name && this.$targetEl.name !== name) this.$targetEl.name = name

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

    this.clearDate = () => this.flatpickrInstance.clear()
    this.$btnClear.addEventListener('click', this.clearDate)
  }
})
