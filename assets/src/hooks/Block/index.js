import autosize from 'autosize'
import { gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.autosizeElements()
  },

  autosizeElements() {
    this.autosized = this.el.querySelectorAll('[data-autosize]')
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    this.autosizeElements()
  }
})
