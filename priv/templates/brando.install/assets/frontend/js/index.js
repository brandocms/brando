/**
 * UNIVERS/TWINED APPLICATION FRONTEND
 * (c) 2019 UNIVERS/TWINED TM
 */

// polyfills
import 'core-js/stable'
import 'regenerator-runtime/runtime'
import 'custom-event-polyfill'
import 'picturefill'

import {
  // Breakpoints,
  Cookies,
  Fader,
  FixedHeader,
  HeroSlider,
  Lightbox,
  Links,
  MobileMenu,
  Moonwalk,
  Typography,

  TweenLite,
  Sine,
  Power3,
  TimelineLite,
  imagesLoaded
} from 'jupiter'

import '../css/app.scss'

TweenLite.defaultEase = Sine.easeOut

class Application {
  constructor() {
    this.fader = null
  }

  initialize() {
    this.lightbox = new Lightbox()
    this.fader = new Fader(this, document.querySelector('#fader'))

    const heroSlider = document.querySelector('[data-hero-slider]')
    if (heroSlider) {
      this.heroSlider = new HeroSlider(heroSlider)
    }

    this.header = new FixedHeader(
      document.querySelector('header'),
      {
        default: {
          enterDelay: 0.5,
          offset: 8,
          offsetSmall: 10,
          offsetBg: 50,
          regBgColor: 'transparent'
        }
      }
    )

    this.mobileMenu = new MobileMenu({
      onResize: (m) => {
        if (document.body.classList.contains('open-menu')) {
          TweenLite.to(m.bg, 0.1, { height: window.innerHeight })
        }
      }
    })

    this.links = new Links(this)
    this.cookies = new Cookies()
    this.typography = new Typography()

    this._emitInitializedEvent()
    setTimeout(this.ready.apply(this), 350)
  }

  ready() {
    this.fader.out()
  }

  _emitInitializedEvent() {
    const initializedEvent = new window.CustomEvent('application:initialized')
    window.dispatchEvent(initializedEvent)
  }

  _emitReadyEvent() {
    const readyEvent = new window.CustomEvent('application:ready')
    window.dispatchEvent(readyEvent)
  }
}

const app = new Application()

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
