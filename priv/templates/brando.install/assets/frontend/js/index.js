/**
 * TWINED APPLICATION FRONTEND
 * (c) 2018 UNIVERS/TWINED TM
 */

import imagesLoaded from 'imagesloaded'
import { TweenLite, Sine } from 'gsap/TweenMax'

import { initializeLightbox } from './lightbox'
import { initializeNavigation, navigationReady } from './navigation'
import { initializeMoonwalk, moonwalkReady } from './moonwalk'
import { initializeCookies } from './cookies'

import '../css/app.scss'

TweenLite.defaultEase = Sine.easeOut

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  ready()
} else {
  document.addEventListener('DOMContentLoaded', ready)
}

function ready () {
  initializeLightbox()
  initializeMoonwalk()
  initializeNavigation()
  initializeCookies()

  imagesLoaded(document.querySelector('body'), function (instance) {
    setTimeout(setReady, 500)
  })
}

function setReady () {
  const body = document.querySelector('body')
  const fader = document.querySelector('#fader')

  body.classList.remove('unloaded')

  navigationReady()
  moonwalkReady()

  TweenLite.to(fader, 1, {
    opacity: 0,
    onComplete: () => {
      fader.style.display = 'none'
    }
  })
}

let App = {}

export default App
