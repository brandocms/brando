import { TweenLite, Power3 } from 'gsap/TweenMax'

export default class HeroSlider {
  constructor (el) {
    this.el = el
    this.currentSlide = 0
    this.slideCount = 0
    this.zIdxVisible = 5
    this.zIdxNext = 4
    this.zIdxReg = 3
    this.interval = 7000
    this.duration = 4
  }

  initialize () {
    // style the container
    this.el.style.position = 'absolute'
    this.el.style.top = 0
    this.el.style.left = 0
    this.el.style.width = '100%'
    this.el.style.height = '100%'
    this.el.style.overflow = 'hidden'

    // style the slides
    this.slides = this.el.querySelectorAll('.hero-slide')
    this.slideCount = this.slides.length - 1

    console.log(this)

    this.slides.forEach(s => {
      s.style.zIndex = this.zidxReg
      s.style.position = 'absolute'
      s.style.top = 0
      s.style.left = 0
      s.style.width = '100%'
      s.style.height = '100%'
      let img = s.querySelector('div')
      if (img) {
        img.style.backgroundPosition = '50% 50%'
        img.style.backgroundRepeat = 'no-repeat'
        img.style.backgroundSize = 'cover'
        img.style.position = 'absolute'
        img.style.top = 0
        img.style.left = 0
        img.style.width = '100%'
        img.style.height = '100%'
      } else {
        console.error('==> MISSING .hero-slide-img with background image inside .hero-slide')
      }
    })

    this.slides[0].style.zIndex = this.zIdxVisible
    this.slides[1].style.zIndex = this.zIdxNext

    setInterval(() => { this.next() }, this.interval)
  }

  next () {
    let prevSlide
    let nextSlide

    if (this.currentSlide === this.slideCount) {
      prevSlide = this.slides[this.currentSlide]
      // last slide --> next slide will be 0
      this.currentSlide = 0
      nextSlide = this.slides[this.currentSlide + 1]
    } else {
      prevSlide = this.slides[this.currentSlide]
      this.currentSlide = this.currentSlide + 1
      if (this.currentSlide === this.slideCount) {
        nextSlide = this.slides[0]
      } else {
        nextSlide = this.slides[this.currentSlide + 1]
      }
    }

    let slide = this.slides[this.currentSlide]

    TweenLite.set(slide, {
      opacity: 0,
      zIndex: this.zIdxVisible
    })

    TweenLite.set(nextSlide, {
      opacity: 0
    })

    TweenLite.to(slide, this.duration, {
      opacity: 1,
      force3D: true,
      ease: Power3.easeInOut,
      onComplete: () => {
        nextSlide.style.zIndex = this.zIdxNext
        slide.style.zIndex = this.zIdxReg
        prevSlide.style.zIndex = this.zIdxReg
        TweenLite.set(prevSlide, {
          opacity: 0
        })
      }
    })
  }
}
