import { gsap } from '@brandocms/jupiter'

const calc = (c, mw, w) => {
  return Math.round(((c - mw) / w) * 100)
}

export default (app) => ({
  mounted() {
    console.log('==> Image FocalPoint mounted')
    const field = this.el.dataset.field
    this.movePoint(this.el, this.el.dataset.x, this.el.dataset.y)

    this.el.addEventListener('click', ({ clientX, clientY }) => {
      const { left, width, top, height } = this.el.getBoundingClientRect()
      const x = calc(clientX, left, width)
      const y = calc(clientY, top, height)
      this.el.dataset.x = x
      this.el.dataset.y = y
      this.movePoint(this.el, x, y)
      this.pushEvent('update_focal_point', { x, y, field })
    })
  },

  updated() {
    console.log('==> Image FocalPoint updated')
    if (this.previousX !== this.el.dataset.x || this.previousY !== this.el.dataset.y) {
      console.log('movepoint!')
      this.movePoint(this.el, this.el.dataset.x, this.el.dataset.y)
    }
  },

  movePoint(rootEl, x, y) {
    const fpEl = rootEl.querySelector('.focus-point-pin')
    gsap.to(fpEl, { left: `${x}%`, top: `${y}%`, duration: 0.2, ease: 'sine.out' })
    this.previousX = x
    this.previousY = y
    setTimeout(() => {
      fpEl.classList.add('visible')
    }, 250)
  }
})