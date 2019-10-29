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
  Lazyload,
  Lightbox,
  Links,
  MobileMenu,
  Moonwalk,
  Typography,

  TweenLite,
  Sine,
  Power3,
  imagesLoaded,
  SR
} from 'jupiter'

import Slider from './slider'
import '../css/app.scss'

TweenLite.defaultEase = Sine.easeOut

class Application {
  constructor () {
    this.fader = null
  }

  initialize () {
    this.lightbox = new Lightbox()
    this.fader = new Fader(this, document.querySelector('#fader'))

    const heroSlider = document.querySelector('.hero-slider')
    if (heroSlider) {
      this.heroSlider = new HeroSlider(heroSlider)
    }

    this.moonwalk = new Moonwalk()

    this.header = new FixedHeader(
      document.querySelector('header'),
      {
        default: {
          offset: 8,
          offsetSmall: 10,
          offsetBg: 50,
          regBgColor: 'transparent'
        },

        sections: {
          index: {
            offsetBg: '#content'
          }
        }
      }
    )

    this.mobileMenu = new MobileMenu()
    this.links = new Links(this)
    this.cookies = new Cookies()
    this.typography = new Typography()
    this.lazyload = new Lazyload()
    // this.breakpoints = new Breakpoints()
    this._emitInitializedEvent()
    setTimeout(this.ready.apply(this), 350)
  }

  ready () {
    this.fader.out()
  }

  _emitInitializedEvent () {
    const initializedEvent = new window.CustomEvent('application:initialized')
    window.dispatchEvent(initializedEvent)
  }

  _emitReadyEvent () {
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

