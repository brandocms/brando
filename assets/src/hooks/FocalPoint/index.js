import { animate, animationTracker, ease } from '../../motion'

const calc = (c, mw, w) => {
  return Math.round(((c - mw) / w) * 100)
}

export default app => ({
  mounted() {
    this.animations = animationTracker()
    const field = this.el.dataset.field
    this.movePoint(this.el, this.el.dataset.x, this.el.dataset.y)

    this.el.addEventListener('click', ({ clientX, clientY }) => {
      const { left, width, top, height } = this.el.getBoundingClientRect()
      const x = calc(clientX, left, width)
      const y = calc(clientY, top, height)
      this.el.dataset.x = x
      this.el.dataset.y = y
      this.movePoint(this.el, x, y)
      this.pushEventTo(this.el, 'update_focal_point', { x, y, field })
    })
  },

  updated() {
    if (this.previousX !== this.el.dataset.x || this.previousY !== this.el.dataset.y) {
      this.movePoint(this.el, this.el.dataset.x, this.el.dataset.y)
    }
  },

  movePoint(rootEl, x, y) {
    const fpEl = rootEl.querySelector('.focus-point-pin')
    this.animations.track(animate(fpEl, { left: `${x}%`, top: `${y}%` }, { duration: 0.2, ease: ease.sineOut }))
    this.previousX = x
    this.previousY = y
    clearTimeout(this.visibleTimer)
    this.visibleTimer = setTimeout(() => {
      fpEl.classList.add('visible')
    }, 250)
  },

  destroyed() {
    this.animations.stopAll()
    clearTimeout(this.visibleTimer)
  }
})
