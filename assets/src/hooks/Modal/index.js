import { gsap } from '@brandocms/jupiter'

export default (app) => ({
  show() {
    const timeline = gsap.timeline()
    timeline
      .set(this.el, { display: 'flex' })
      .set(this.elements.backdrop, { display: 'block', opacity: 0 })
      .set(this.elements.dialog, { opacity: 0, y: 30 })
      .to(this.elements.backdrop, { opacity: 1, duration: 0.25 })
      .to(this.elements.dialog, { opacity: 1, duration: 0.3 }, '-=0.2')
      .to(this.elements.dialog, { y: 0, duration: 0.3, ease: 'circ.out' }, '<')
      .set(this.elements.dialog, { clearProps: 'transform' })
  },

  hide() {
    const timeline = gsap.timeline()
    timeline
      .to(this.elements.dialog, { opacity: 0, duration: 0.3 })
      .to(this.elements.dialog, { y: 30, duration: 0.3, ease: 'circ.in' }, '<')
      .to(this.elements.backdrop, { opacity: 0, duration: 0.25 }, '-=0.2')
      .set(this.el, { display: 'none' })
      .set(this.elements.dialog, { clearProps: 'transform' })
  },

  mounted() {
    this.elements = {}
    this.elements.backdrop = this.el.querySelector('.modal-backdrop')
    this.elements.dialog = this.el.querySelector('.modal-dialog')

    this.handleEvent(`b:modal:show:${this.el.id}`, payload => {
      console.log(`b:modal:show:${this.el.id}`)
      this.show()
    })

    this.handleEvent(`b:modal:hide:${this.el.id}`, payload => {
      console.log(`b:modal:hide:${this.el.id}`)
      this.hide()
    })
  }
})