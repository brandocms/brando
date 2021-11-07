import { gsap } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')

    this.submitListenerEvent = this.submitListener.bind(this)
    window.addEventListener('keydown', this.submitListenerEvent, false)

    this.handleEvent(`b:validate`, () => {
      this.$input.dispatchEvent(new Event('input', { bubbles: true }))
    })

    this.handleEvent(`b:live_preview`, ({ cache_key: cacheKey }) => {
      window.open(
        '/__livepreview?key=' + cacheKey,
        '_blank'
      )
    })
  },

  destroyed() { 
    window.removeEventListener('keydown', this.submitListenerEvent, false)
  },

  submitListener (ev) {
    if (ev.metaKey && ev.key === 's') {
      ev.preventDefault();
      this.$form.dispatchEvent(new Event('submit', { bubbles: true }))
    }
  }
})