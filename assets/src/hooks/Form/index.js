import { Dom, gsap } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')
    this.$livePreview = this.el.querySelector('.live-preview')

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
      // hide nav
      app.navigation.fsToggle.classList.toggle('minimized')
      app.navigation.setFullscreen(true)

      const lpDivider = Dom.find('.live-preview-divider')

      lpDivider.addEventListener('mousedown', this.lpResizer)

      setTimeout(() => {
        // set widths
        this.lpIframe = document.querySelector('.live-preview iframe')
        this.setPreviewWidth(this.el, livePreview, 600)
        this.setPreviewTarget('desktop')
        gsap.to(this.$livePreview, { opacity: 1, ease: 'none', delay: 1 })

        // bind target buttons
        const targetBtns = this.$livePreview.querySelectorAll('button')
        Array.from(targetBtns).forEach(targetBtn => {
          targetBtn.addEventListener('click', () => {
            const target = targetBtn.dataset.livePreviewTarget
            this.lpIframe.dataset.livePreviewDevice = target
            this.setPreviewTarget(target)
          })
        })
      }, 500)
    })

    // this.$input.dispatchEvent(new Event('input', { bubbles: true }))
  },

  setPreviewWidth (width) {
    gsap.to(this.el, { width: `-=${width}` })
    gsap.set(this.$livePreview, { display: 'block', opacity: 0 })
    gsap.set(this.$livePreview, { width: width, ease: 'sine.inOut' })
  },

  lpResizer (e) {
    function mousemove(e) {
      let newX = prevX - e.x
      // leftPane.style.width = leftPanel.width - newX + "px"
      console.log(newX)
    }

    function mouseup() {
      window.removeEventListener('mousemove', mousemove)
      window.removeEventListener('mouseup', mouseup)
    }

    window.addEventListener('mousemove', mousemove)
    window.addEventListener('mouseup', mouseup)

    let prevX = e.x
    const leftPanel = this.el.getBoundingClientRect()
    // const leftPanel = leftPane.getBoundingClientRect()
  },

  setPreviewTarget(target) {
    let deviceWidth
    let previewWidth
    let upFactor
    let downFactor

    switch (target) {
      case 'desktop':
        deviceWidth = 1440
        previewWidth = 600
        upFactor = deviceWidth / previewWidth
        downFactor = previewWidth / deviceWidth
        gsap.set(this.lpIframe, { scale: downFactor })
        gsap.set(this.lpIframe, { height: window.innerHeight * upFactor })
        break

      case 'tablet':
        deviceWidth = 768
        previewWidth = 600
        upFactor = deviceWidth / previewWidth
        downFactor = previewWidth / deviceWidth
        gsap.set(this.lpIframe, { scale: downFactor })
        gsap.set(this.lpIframe, { height: window.innerHeight * upFactor })
        break

      case 'mobile':
        deviceWidth = 375
        previewWidth = 600
        upFactor = deviceWidth / previewWidth
        downFactor = previewWidth / deviceWidth
        gsap.set(this.lpIframe, { scale: downFactor })
        gsap.set(this.lpIframe, { height: window.innerHeight * upFactor })
        break
    }
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