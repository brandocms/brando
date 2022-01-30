import { gsap } from '@brandocms/jupiter'

export default (app) => ({
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

    this.handleEvent(`b:live_preview`, () => {
      const deviceWidth = 1440
      const previewWidth = 600
      const upFactor = deviceWidth / previewWidth
      const downFactor = previewWidth / deviceWidth
      // hide nav
      app.navigation.fsToggle.classList.toggle('minimized')
      app.navigation.setFullscreen(true)

      setTimeout(() => {
        // set widths
        console.log('set widths')
        const brandoForm = document.querySelector('.brando-form')
        const livePreview = document.querySelector('.live-preview')
        const iframe = document.querySelector('.live-preview iframe')
        gsap.to(brandoForm, { width: `-=${previewWidth}` })
        gsap.set(livePreview, { display: 'block', opacity: 0 })
        gsap.set(livePreview, { width: previewWidth })
        gsap.set(iframe, { scale: downFactor })
        gsap.set(iframe, { height: window.innerHeight * upFactor })
        gsap.to(livePreview, { opacity: 1, ease: 'none', delay: 1 })
      }, 500)
    })

    // this.$input.dispatchEvent(new Event('input', { bubbles: true }))
  },

  destroyed() { 
    window.removeEventListener('keydown', this.submitListenerEvent, false)
  },

  submitListener (ev) {
    if (ev.metaKey && ev.key === 's') {
      ev.preventDefault();
      this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
    }
  }
})