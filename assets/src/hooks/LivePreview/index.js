import { Dom, Events } from '@brandocms/jupiter'
import { prefersReducedMotion } from '../../motion'

const DEVICES = { desktop: { width: 1440 }, tablet: { width: 768, height: 1024 }, mobile: { width: 375, height: 812 } }

export default app => ({
  mounted() {
    this.active = false
    // Kept from mount: when the preview closes from the server, the hook's
    // element is already detached in destroyed().
    this.$form = this.el.closest('.brando-form')
    this.$livePreview = this.el.querySelector('.live-preview')
    this.$livePreview.inert = true
    this.$iframeWrapper = this.el.querySelector('.live-preview-iframe-wrapper')
    this.$iframe = this.el.querySelector('iframe')
    this.$divider = this.el.querySelector('.live-preview-divider')
    this.$notice = this.el.querySelector('.live-preview-notice')
    this.$notice.textContent = ''
    this.handleEvent('b:live_preview', () => { if (!this.active) this.toggle() })
    this.handleEvent('b:live_preview_notice', () => this.showNotice())
    this.windowResizeListener = () => this.windowResize()
    this.pointerDown = event => this.startResize(event)
    this.pointerMove = event => {
      if (!this.drag || event.pointerId !== this.drag.id) return
      this.setPreviewTarget(this.livePreviewTarget, this.drag.width + this.drag.x - event.clientX)
    }
    this.pointerEnd = () => this.stopResize()
    this.keyResize = event => {
      if (!this.active) return
      const widths = { ArrowLeft: this.livePreviewWidth + 24, ArrowRight: this.livePreviewWidth - 24, Home: 320, End: this.lpMaxWidth }
      if (!(event.key in widths)) return
      event.preventDefault()
      this.setPreviewTarget(this.livePreviewTarget, widths[event.key])
    }
    this.click = event => {
      const target = event.target.closest('[data-live-preview-target]')
      if (target) {
        const device = target.dataset.livePreviewTarget
        this.setPreviewTarget(device, device === 'mobile' ? 375 : this.livePreviewWidth, 0.35)
      }
      if (event.target.closest('.live-preview-blank') && this.active) this.toggle()
    }
    this.el.addEventListener('click', this.click)
    this.$divider.addEventListener('pointerdown', this.pointerDown)
    this.$divider.addEventListener('pointermove', this.pointerMove)
    this.$divider.addEventListener('pointerup', this.pointerEnd)
    this.$divider.addEventListener('pointercancel', this.pointerEnd)
    this.$divider.addEventListener('lostpointercapture', this.pointerEnd)
    this.$divider.addEventListener('keydown', this.keyResize)
    window.addEventListener('blur', this.pointerEnd)
  },

  // Lifts the form's max width while the preview takes the right side
  // (Form.css). Sticky, as the form element is patched by LiveView.
  markPreviewing(previewing) {
    if (this.$form) this.js()[previewing ? 'addClass' : 'removeClass'](this.$form, 'is-previewing')
  },

  toggle() {
    this.active = !this.active
    this.$livePreview.inert = !this.active
    this.pushEventTo(Dom.find('#brando-nav'), 'toggle_nav', { minimized: this.active })
    this.markPreviewing(this.active)
    if (this.active) {
      this.lpSetMaxWidth()
      window.addEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)
      this.setPreviewTarget('desktop', Math.min(600, this.lpMaxWidth), 0.35)
      this.entrance = this.$livePreview.animate([{ opacity: 0 }, { opacity: 1 }], {
        duration: prefersReducedMotion() ? 1 : 350,
      })
    } else {
      this.stopResize()
      window.removeEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)
      this.setPreviewWidth(0, 0.3)
    }
  },

  // A status line over the top of the preview (`.live-preview-notice`), with
  // its text from the server-rendered `data-message`.
  showNotice() {
    clearTimeout(this.noticeTimer)
    this.$notice.textContent = this.$notice.dataset.message
    this.$notice.classList.add('is-visible')
    this.noticeTimer = setTimeout(() => {
      this.$notice.classList.remove('is-visible')
      this.$notice.textContent = ''
    }, 6000)
  },

  lpSetMaxWidth() {
    this.lpMaxWidth = Math.max(320, window.innerWidth - 805)
    this.$divider.setAttribute('aria-valuemax', this.lpMaxWidth)
  },

  windowResize() {
    this.lpSetMaxWidth()
    this.setPreviewTarget(this.livePreviewTarget, this.livePreviewWidth)
  },

  startResize(event) {
    if (event.button !== 0 || !this.active) return
    event.preventDefault()
    this.stopResize()
    this.drag = { id: event.pointerId, x: event.clientX, width: this.$livePreview.getBoundingClientRect().width }
    this.$divider.setPointerCapture(event.pointerId)
    this.$livePreview.classList.add('is-resizing')
    this.$divider.focus({ preventScroll: true })
  },

  stopResize() {
    if (!this.drag) return
    const { id } = this.drag
    this.drag = null
    if (this.$divider.hasPointerCapture(id)) this.$divider.releasePointerCapture(id)
    this.$livePreview.classList.remove('is-resizing')
  },

  setPreviewWidth(width, duration = 0) {
    const from = this.$livePreview.getBoundingClientRect().width
    this.widthAnimation?.cancel()
    this.$livePreview.style.width = `${width}px`
    if (duration && !prefersReducedMotion()) {
      this.widthAnimation = this.$livePreview.animate([{ width: `${from}px` }, { width: `${width}px` }], {
        duration: duration * 1000, easing: 'cubic-bezier(0.22, 1, 0.36, 1)',
      })
    }
  },

  setPreviewTarget(target, width, duration = 0) {
    const device = DEVICES[target]
    if (!device) return
    width = Math.max(320, Math.min(width, this.lpMaxWidth))
    this.livePreviewTarget = target
    this.livePreviewWidth = width
    this.setPreviewWidth(width, duration)
    this.$iframe.dataset.livePreviewDevice = target
    this.$divider.setAttribute('aria-valuenow', Math.round(width))
    this.el.querySelectorAll('[data-live-preview-target]').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.livePreviewTarget === target))
    })
    const availableHeight = window.innerHeight - this.el.querySelector('.live-preview-targets').getBoundingClientRect().height
    Object.assign(this.$iframe.style, {
      transform: `scale(${width / device.width})`,
      width: `${device.width}px`,
      height: `${device.height || availableHeight * device.width / width}px`,
    })
    this.$iframeWrapper.style.height = `${availableHeight}px`
  },

  destroyed() {
    this.markPreviewing(false)
    clearTimeout(this.noticeTimer)
    this.stopResize()
    this.entrance?.cancel()
    this.widthAnimation?.cancel()
    this.el.removeEventListener('click', this.click)
    this.$divider.removeEventListener('pointerdown', this.pointerDown)
    this.$divider.removeEventListener('pointermove', this.pointerMove)
    this.$divider.removeEventListener('pointerup', this.pointerEnd)
    this.$divider.removeEventListener('pointercancel', this.pointerEnd)
    this.$divider.removeEventListener('lostpointercapture', this.pointerEnd)
    this.$divider.removeEventListener('keydown', this.keyResize)
    window.removeEventListener('blur', this.pointerEnd)
    window.removeEventListener(Events.APPLICATION_RESIZE, this.windowResizeListener)
  },
})
