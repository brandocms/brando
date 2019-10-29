import { TweenLite, Sine } from 'jupiter'
import Flickity from 'flickity'
import 'flickity-imagesloaded'
TweenLite.defaultEase = Sine.easeOut

export default class Slider {
  constructor (el, type = 'index') {
    this.el = el
    this.glide = null
    this.follower = null
    this.followerVisible = false
    this.arrow = null
    this.type = type
    this.track = this.el.querySelector('[data-glide-el="track"]')
    this.projectsEl = this.el.querySelector('.glide__slides')
    this.panels = this.el.querySelectorAll('.glide__slide')
    this.links = this.el.querySelectorAll('a')
    this.subtractX = 0
    this.subbedX = false

    this.setupGlider()
  }

  setupGlider () {
    let c
    if (document.body.getAttribute('data-script') === 'index') {
      c = this.calcCellAlign()
    } else {
      c = 0.22
    }
    this.glide = new Flickity(this.el, {
      // options
      adaptiveHeight: false,
      cellAlign: c, // 0.1833
      wrapAround: true,
      percentPosition: true,
      // freeScroll: true,
      pageDots: false,
      prevNextButtons: false,
      imagesLoaded: true
    })

    const modulo = function (num, div) {
      return ((num % div) + div) % div
    }

    let _this = this

    Flickity.prototype.positionSlider = function () {
      var x = this.x - _this.subtractX
      // wrap position around
      if (this.options.wrapAround && this.cells.length > 1) {
        x = modulo(x, this.slideableWidth)
        x = x - this.slideableWidth
        this.shiftWrapCells(x)
      }
      this.setTranslateX(x, false)
      this.dispatchScrollEvent()
    }

    this.calculateSliderPos()
  }

  calculateSliderPos () {
    this.glide.resize()
    let h5 = this.el.parentNode.parentNode.querySelector('h5')
    let sel = this.el.querySelector('.is-selected')

    if (h5) {
      let headPos = h5.getBoundingClientRect().left
      let selPos = sel.getBoundingClientRect().left
      this.subtractX = selPos - headPos
      this.glide.positionSlider()
    }
  }

  calcCellAlign () {
    let h5 = this.el.parentNode.parentNode.querySelector('h5')

    if (h5) {
      let headPos = h5.getBoundingClientRect().left
      let fViewport = document.querySelector('header')

      return headPos / fViewport.offsetWidth
    }

    return 'center'
  }
}
