/**
 * A header that stays fixed. Hides when scrolling down and is revealed on scrolling up.
 */

import { TweenLite, Power3 } from 'gsap/TweenMax'
// import debounce from 'lodash/debounce'

export default class FixedHeader {
  constructor (el, opts = {}) {
    if (!el) {
      console.error('TWINED/FIXEDHEADER: NO ELEMENT PROVIDED TO FIXEDHEADER')
    }
    this.el = el
    this._pinned = true
    this._top = false
    this._bottom = false
    this._small = false
    this._altBg = false
    this._hasScrolled = false
    this.lastKnownScrollY = 0
    this.currentScrollY = 0

    Object.assign(this, {
      canvas: window,
      slideIn: true,
      slideInDelay: 1.4,
      tolerance: 3,
      offset: 0, // how far from the top before we trigger hide
      offsetSmall: 50, // how far from the top before we trigger the shrinked padding,
      offsetBg: 200, // how far down before changing backgroundcolor
      regBgColor: 'transparent',
      altBgColor: '#ffffff',
      onAltBg: () => {},
      onNotAltBg: () => {},
      onSmall: () => {},
      onNotSmall: () => {},
      onPin: () => {},
      onUnpin: () => {}
    }, opts)
  }

  initialize () {
    // bind to canvas scroll
    this.lastKnownScrollY = this.getScrollY()
    this.currentScrollY = this.lastKnownScrollY

    this.redraw(true)
    this.loop()
  }

  loop () {
    const _chkUpdate = () => {
      if (!this._hasScrolled) {
        window.requestAnimationFrame(() => { this.redraw(false) })
      }
      this._hasScrolled = true
      window.requestAnimationFrame(_chkUpdate)
    }

    _chkUpdate()
  }

  checkSize (force) {
    if (this.currentScrollY > this.offsetSmall) {
      if (force) {
        this.small()
      } else {
        if (!this._small) {
          this.small()
        }
      }
    } else {
      if (force) {
        this.notSmall()
      } else {
        if (this._small) {
          this.notSmall()
        }
      }
    }
  }

  checkBg (force) {
    if (this.currentScrollY > this.offsetBg) {
      if (force) {
        this.altBg()
      } else {
        if (!this._altBg) {
          this.altBg()
        }
      }
    } else {
      if (force) {
        this.notAltBg()
      } else {
        if (this._altBg) {
          this.notAltBg()
        }
      }
    }
  }

  checkTop (force) {
    if (this.currentScrollY <= this.offset) {
      if (force) {
        this.top()
      } else {
        if (!this._top) {
          this.top()
        }
      }
    } else {
      if (force) {
        this.notTop()
      } else {
        if (this._top) {
          this.notTop()
        }
      }
    }
  }

  checkBot (force) {
    if (this.currentScrollY + this.getViewportHeight() >= this.getScrollerHeight()) {
      if (force) {
        this.bottom()
      } else {
        if (!this._bottom) {
          this.bottom()
        }
      }
    } else {
      if (force) {
        this.notBottom()
      } else {
        if (this._bottom) {
          this.notBottom()
        }
      }
    }
  }

  checkPin (force, toleranceExceeded) {
    if (this.shouldUnpin(toleranceExceeded)) {
      if (force) {
        this.unpin()
      } else {
        if (this._pinned) {
          this.unpin()
        }
      }
    } else if (this.shouldPin(toleranceExceeded)) {
      if (force) {
        this.pin()
      } else {
        if (!this._pinned) {
          this.pin()
        }
      }
    }
  }

  redraw (force = false) {
    if (force && this.slideIn) {
      TweenLite.set(this.el, { yPercent: -100 })
      TweenLite.to(this.el, 1, { yPercent: 0, delay: this.slideInDelay, ease: Power3.easeOut })
      this.checkSize(force)
      this.checkBg(force)
      return
    }

    this.currentScrollY = this.getScrollY()
    const toleranceExceeded = this.toleranceExceeded()

    if (this.isOutOfBounds()) { // Ignore bouncy scrolling in OSX
      return
    }

    this.checkSize(force)
    this.checkBg(force)
    this.checkTop(force)
    this.checkBot(force)
    this.checkPin(force, toleranceExceeded)

    this.lastKnownScrollY = this.currentScrollY
    this._hasScrolled = false
  }

  notTop () {
    this._top = false
    this.el.removeAttribute('data-header-top')
    this.el.setAttribute('data-header-not-top', '')
  }

  top () {
    this._top = true
    this.el.setAttribute('data-header-top', '')
    this.el.removeAttribute('data-header-not-top')
  }

  notBottom () {
    this._bottom = false
    this.el.setAttribute('data-header-not-bottom', '')
    this.el.removeAttribute('data-header-bottom')
  }

  bottom () {
    this._bottom = true
    this.el.setAttribute('data-header-bottom', '')
    this.el.removeAttribute('data-header-not-bottom')
  }

  unpin () {
    this._pinned = false
    this.el.setAttribute('data-header-unpinned', '')
    this.el.removeAttribute('data-header-pinned')
    this.onUnpin(this)
  }

  pin () {
    this._pinned = true
    this.el.setAttribute('data-header-pinned', '')
    this.el.removeAttribute('data-header-unpinned')
    this.onPin(this)
  }

  notSmall () {
    this._small = false
    this.el.setAttribute('data-header-big', '')
    this.el.removeAttribute('data-header-small')
    this.onNotSmall(this)
  }

  small () {
    this._small = true
    this.el.setAttribute('data-header-small', '')
    this.el.removeAttribute('data-header-big')
    this.onSmall(this)
  }

  notAltBg () {
    this._altBg = false
    this.el.setAttribute('data-header-reg-bg', '')
    this.el.removeAttribute('data-header-alt-bg')
    this.onNotAltBg(this)
  }

  altBg () {
    this._altBg = true
    this.el.setAttribute('data-header-alt-bg', '')
    this.el.removeAttribute('data-header-reg-bg')
    this.onAltBg(this)
  }

  shouldUnpin (toleranceExceeded) {
    const scrollingDown = this.currentScrollY > this.lastKnownScrollY
    const pastOffset = this.currentScrollY >= this.offset

    return scrollingDown && pastOffset && toleranceExceeded
  }

  shouldPin (toleranceExceeded) {
    const scrollingUp = this.currentScrollY < this.lastKnownScrollY
    const pastOffset = this.currentScrollY <= this.offset

    return (scrollingUp && toleranceExceeded) || pastOffset
  }

  isOutOfBounds () {
    const pastTop = this.currentScrollY < 0
    const pastBottom = this.currentScrollY + this.getScrollerPhysicalHeight() > this.getScrollerHeight()

    return pastTop || pastBottom
  }

  getScrollerPhysicalHeight () {
    return (this.canvas === window || this.canvas === document.body)
      ? this.getViewportHeight()
      : this.getElementPhysicalHeight(this.canvas)
  }

  getScrollerHeight () {
    return (this.canvas === window || this.canvas === document.body)
      ? this.getDocumentHeight()
      : this.getElementHeight(this.canvas)
  }

  getDocumentHeight () {
    const body = document.body
    const documentElement = document.documentElement

    return Math.max(
      body.scrollHeight, documentElement.scrollHeight,
      body.offsetHeight, documentElement.offsetHeight,
      body.clientHeight, documentElement.clientHeight
    )
  }

  getViewportHeight () {
    return window.innerHeight ||
      document.documentElement.clientHeight ||
      document.body.clientHeight
  }

  getElementHeight (el) {
    return Math.max(
      el.scrollHeight,
      el.offsetHeight,
      el.clientHeight
    )
  }

  getElementPhysicalHeight (el) {
    return Math.max(
      el.offsetHeight,
      el.clientHeight
    )
  }

  getScrollY () {
    return (this.canvas.pageYOffset !== undefined)
      ? this.canvas.pageYOffset
      : (this.canvas.scrollTop !== undefined)
        ? this.canvas.scrollTop
        : (document.documentElement || document.body.parentNode || document.body).scrollTop
  }

  toleranceExceeded () {
    return Math.abs(this.currentScrollY - this.lastKnownScrollY) >= this.tolerance
  }
}
