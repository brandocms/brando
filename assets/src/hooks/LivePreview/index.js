import { Dom, Events } from '@brandocms/jupiter'
import { animate, animationTracker, ease, set } from '../../motion'

export default app => ({
  mounted() {
    this.active = false
    this.animations = animationTracker()

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
    // minimize menu
    const $nav = Dom.find('#brando-nav')
    this.pushEventTo($nav, 'toggle_nav', { minimized: this.active })

    const lpDivider = Dom.find('.live-preview-divider')
    this.$livePreview = this.el.querySelector('.live-preview')
    this.$iframeWrapper = document.querySelector('.live-preview-iframe-wrapper')
    this.$iframe = document.querySelector('.live-preview iframe')

    if (this.active) {
      lpDivider.addEventListener('mousedown', this.resizeListener)

      this.lpSetMaxWidth()
      window.addEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)

      // Hidden now: Motion only applies the first keyframe once the delay ends.
      set(this.$livePreview, { opacity: 0 })
      this.setPreviewTarget('desktop', this.lpMaxWidth > 600 ? 600 : this.lpMaxWidth, 0.5)
      this.animations.track(
        animate(this.$livePreview, { opacity: [0, 1] }, { ease: ease.none, duration: 0.35, delay: 0.7 })
      )

      // bind target buttons
      const targetBtns = this.$livePreview.querySelectorAll('button[data-live-preview-target]')
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
    this.animations.track(animate(this.$livePreview, { width: `${width}px` }, { ease: ease.sineInOut, duration }))
  },

  destroyed() {
    this.animations.stopAll()
    clearTimeout(this.scaleTimer)
    const lpDivider = Dom.find('.live-preview-divider')
    if (lpDivider) {
      lpDivider.removeEventListener('mousedown', this.resizeListener)
    }
    window.removeEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)
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

    // Only the latest target is scaled for: a drag sets a new width per move.
    clearTimeout(this.scaleTimer)
    this.scaleTimer = setTimeout(() => {
      upFactor = deviceWidth / previewWidth
      downFactor = previewWidth / deviceWidth
      const targetsHeight = Dom.find('.live-preview-targets').getBoundingClientRect().height
      const calcHeight = deviceHeight || (window.innerHeight - targetsHeight) * upFactor
      set(this.$iframe, {
        transform: `scale(${downFactor})`,
        width: `${deviceWidth}px`,
        height: `${deviceHeight || calcHeight}px`,
      })
      set(this.$iframeWrapper, { height: `${window.innerHeight - targetsHeight}px` })
    }, duration * 1000)
  }
})
