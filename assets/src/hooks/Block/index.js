import autosize from 'autosize'
import { gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    const tl = gsap.timeline()
    tl.set(this.el, { y: -8, opacity: 0 })
      .to(this.el, { y: 0, ease: 'power2.out', duration: 0.4 })
      .to(this.el, { opacity: 1, ease: 'none', duration: 0.2 }, '<')
      .call(() => gsap.set(this.el, { clearProps: 'all' }))
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
