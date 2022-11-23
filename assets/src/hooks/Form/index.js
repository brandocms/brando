import { Dom, Events, gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')
    this.paramName = this.$input.name.split('[')[0]
    this.submitListenerEvent = this.submitListener.bind(this)
    window.addEventListener('keydown', this.submitListenerEvent, false)

    this.handleEvent(`b:validate`, opts => {
      if (opts.target) {
        const sel = `[name="${opts.target}"]`
        const target = this.$form.querySelector(sel)
        if (target) {
          if (opts.hasOwnProperty('value')) {
            target.value = opts.value
          }
          target.dispatchEvent(new Event('input', { bubbles: true }))
          return
        }
      }
      this.$input.dispatchEvent(new Event('input', { bubbles: true }))
    })
  },

  destroyed() {
    window.removeEventListener('keydown', this.submitListenerEvent, false)
  },

  submitListener(ev) {
    if (ev.metaKey && ev.shiftKey && ev.key.toLowerCase() === 's') {
      ev.preventDefault()
      this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
      return
    }

    if (ev.metaKey && ev.key === 's') {
      ev.preventDefault()
      this.pushEventTo(this.el, 'save_redirect_target', { save_redirect_target: 'self' })
      this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    }
  }
})
