import { gsap } from '@brandocms/jupiter'
import vanillaClickOutside from 'vanilla-click-outside'

export default (app) => ({
  mounted() {
    this.open = false
    this.$btn = this.el.querySelector('.circle-dropdown-button')
    this.$content = this.$btn.nextElementSibling

    this.$btn.addEventListener('click', e => {
      e.stopPropagation()
      this.toggle()
    })

    this.$content.addEventListener('click', () => this.closeContent())
    vanillaClickOutside(this.$content, (type, event) => {
      if (this.open) {
        this.closeContent()
      }
    })
  },

  toggle() {
    this.open ? this.closeContent() : this.openContent()
  },

  openContent() {
    this.open = true
    this.$btn.classList.add('open')
    const buttonHeight = this.$btn.clientHeight
    const buttonBottom = this.$btn.getBoundingClientRect().y + buttonHeight

    gsap.set(this.$content, { top: buttonHeight + 10, right: 0, opacity: 0, x: -15, display: 'block' })
    const contentRect = this.$content.getBoundingClientRect()

    if (contentRect.height + buttonBottom > window.innerHeight) {
      gsap.set(this.$content, { top: (contentRect.height + 10) * -1 })
    }

    gsap.to(this.$content, { opacity: 1, x: 0, duration: '0.25' })
  },

  closeContent() {
    if (this.open) {
      this.open = false
      this.$btn.classList.remove('open')
      if (this.$content) {
        gsap.to(this.$content, {
          opacity: 0,
          x: -15,
          duration: '0.25',
          onComplete: () => {
            if (this.$content) {
              gsap.set(this.$content, { display: 'none' })
            }
          }
        })
      }
    }
  }
})