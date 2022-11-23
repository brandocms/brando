import { Dom, Events, gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.active = false

    this.handleEvent(`b:live_preview`, () => {
      this.toggle()
    })

    this.windowResizeListener = this.windowResize.bind(this)
    this.resizeListener = this.resizer.bind(this)

    const $blankLink = Dom.find(this.el, '.live-preview-blank')
    $blankLink.addEventListener('click', this.toggle.bind(this))
  },

  toggle() {
    this.active = !this.active
    app.navigation.fsToggle.classList.toggle('minimized')
    app.navigation.setFullscreen(this.active)

    const lpDivider = Dom.find('.live-preview-divider')
    this.$livePreview = this.el.querySelector('.live-preview')
    this.$iframeWrapper = document.querySelector('.live-preview-iframe-wrapper')
    this.$iframe = document.querySelector('.live-preview iframe')

    if (this.active) {
      lpDivider.addEventListener('mousedown', this.resizeListener)

      this.lpSetMaxWidth()
      window.addEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)

      gsap.set(this.$livePreview, { opacity: 0 })
      this.setPreviewTarget('desktop', this.lpMaxWidth > 600 ? 600 : this.lpMaxWidth, 0.5)
      gsap.to(this.$livePreview, { opacity: 1, ease: 'none', duration: 0.35, delay: 0.7 })

      // bind target buttons
      const targetBtns = this.$livePreview.querySelectorAll('button')
      Array.from(targetBtns).forEach(targetBtn => {
        targetBtn.addEventListener('click', () => {
          const target = targetBtn.dataset.livePreviewTarget
          this.$iframe.dataset.livePreviewDevice = target
          this.setPreviewTarget(target, this.livePreviewWidth)
        })
      })
    } else {
      lpDivider.removeEventListener('mousedown', this.resizeListener)
      window.removeEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)
      this.setPreviewTarget('desktop', 0, 0.5)
    }
  },

  windowResize() {
    this.lpSetMaxWidth()
    this.setPreviewTarget('desktop', this.lpMaxWidth > 600 ? 600 : this.lpMaxWidth)
  },

  lpSetMaxWidth() {
    this.lpMaxWidth = window.innerWidth - 805
  },

  resizer(e) {
    const that = this
    function mousemove(e) {
      let newX = prevX - e.x

      const newWidth = lp.width + newX

      if (newWidth < that.lpMaxWidth && newWidth > 320) {
        that.setPreviewTarget(that.livePreviewTarget, newWidth)
      } else {
        mouseup()
      }
    }

    function mouseup() {
      window.removeEventListener('mousemove', mousemove)
      window.removeEventListener('mouseup', mouseup)
    }

    window.addEventListener('mousemove', mousemove)
    window.addEventListener('mouseup', mouseup)

    let prevX = e.x
    const lp = this.$livePreview.getBoundingClientRect()
  },

  setPreviewWidth(width, duration) {
    gsap.to(this.$livePreview, { width: width, ease: 'sine.inOut', duration })
  },

  setPreviewTarget(target, previewWidth, duration = 0) {
    let deviceWidth
    let deviceHeight
    let upFactor
    let downFactor

    switch (target) {
      case 'desktop':
        deviceWidth = 1440
        break

      case 'tablet':
        deviceWidth = 768
        deviceHeight = 1024
        break

      case 'mobile':
        deviceWidth = 375
        deviceHeight = 812
        if (previewWidth !== 375) {
          previewWidth = 375
          duration = 0.5
        }
        break
    }

    this.livePreviewTarget = target
    this.livePreviewWidth = previewWidth
    this.setPreviewWidth(previewWidth, duration)

    setTimeout(() => {
      upFactor = deviceWidth / previewWidth
      downFactor = previewWidth / deviceWidth
      gsap.set(this.$iframe, { scale: downFactor })
      gsap.set(this.$iframe, { width: deviceWidth })
      const targetsHeight = Dom.find('.live-preview-targets').getBoundingClientRect().height
      const calcHeight = deviceHeight || (window.innerHeight - targetsHeight) * upFactor
      gsap.set(this.$iframeWrapper, { height: window.innerHeight - targetsHeight })
      if (deviceHeight) {
        gsap.set(this.$iframe, { height: deviceHeight })
      } else {
        gsap.set(this.$iframe, { height: calcHeight })
      }
    }, duration * 1000)
  }
})
