import autosize from 'autosize'
import { gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    gsap.set(this.el, { y: -8, opacity: 0 })
    gsap.to(this.el, { y: 0, ease: 'power2.out', duration: 0.4 })
    gsap.to(this.el, { opacity: 1, ease: 'none', duration: 0.2 })
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
