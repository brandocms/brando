import { gsap } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')
    // this.$input.dispatchEvent(new Event('input', { bubbles: true }))

    // set drawers off screen
    gsap.set('.drawer', { xPercent: 100 })

    this.handleEvent(`b:validate`, () => {
      this.$input.dispatchEvent(new Event('input', { bubbles: true }))
    })

    /**
     * Open and close side drawers.
     * 
     * We unfortunately have to do this with JS, since if we do not clear the transform
     * any modals triggered from inside the drawers will be bound to the transformed 
     * element and not allowed to overflow. This ruins the backdrop, and also cramps the size
     */
    this.handleEvent('b:drawer:open', ({ id }) => {
      gsap.to(id, { xPercent: 0, ease: 'circ.out', onComplete: () => {
        gsap.set(id, { clearProps: 'transform' })
      }})
    })

    this.handleEvent('b:drawer:close', ({ id }) => {
      gsap.to(id, { xPercent: 100, ease: 'circ.in' })
    })
  }
})