/**
 * UNIVERS/TWINED APPLICATION FRONTEND
 * (c) 2019 UNIVERS/TWINED TM
 */

// polyfills
import 'core-js/stable'
import 'regenerator-runtime/runtime'
import 'custom-event-polyfill'
import 'intersection-observer'
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

const FIXED_HEADER_OPTS = {
  default: {
    enterDelay: 0.5,
    offset: 8,
    offsetSmall: 10,
    offsetBg: 50,
    regBgColor: 'transparent'
  }
}

const MOBILE_MENU_OPTS = {
  onResize: (m) => {
    if (document.body.classList.contains('open-menu')) {
      TweenLite.to(m.bg, 0.1, { height: window.innerHeight })
    }
  }
}

const MOONWALK_OPTS = {
  walks: {
    default: {
      distance: '4px'
    }
  }
}

class Application {
  constructor() {
    this.fader = null
  }

  initialize() {
    this.initializedEvent = new window.CustomEvent('application:initialized')
    this.readyEvent = new window.CustomEvent('application:ready')

    window.addEventListener('application:ready', () => {
      // on ready
      this.links = new Links(this)
    })

    this.lightbox = new Lightbox()
    this.fader = new Fader(this, '#fader')
    this.moonwalk = new Moonwalk(MOONWALK_OPTS)
    this.heroSlider = new HeroSlider('[data-hero-slider]')
    this.header = new FixedHeader('header[data-nav]', FIXED_HEADER_OPTS)
    this.mobileMenu = new MobileMenu(MOBILE_MENU_OPTS)
    this.cookies = new Cookies()
    this.typography = new Typography()

    this._emitInitializedEvent()
    setTimeout(this.ready.apply(this), 350)
  }

  ready() {
    this.fader.out()
  }

  _emitInitializedEvent() {
    window.dispatchEvent(this.initializedEvent)
  }

  _emitReadyEvent() {
    window.dispatchEvent(this.readyEvent)
  }
}

const app = new Application()

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
