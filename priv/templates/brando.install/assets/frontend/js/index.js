/**
 * TWINED APPLICATION FRONTEND
 * (c) 2018 UNIVERS/TWINED TM
 */

import imagesLoaded from 'imagesloaded'
import Velocity from 'velocity-animate'

import { initializeLightbox } from './lightbox'
import { initializeNavigation, navigationReady } from './navigation'
import { initializeMoonwalk, moonwalkReady } from './moonwalk'

import '../css/app.scss'

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  ready()
} else {
  document.addEventListener('DOMContentLoaded', ready)
}

function ready() {
  initializeLightbox()
  initializeMoonwalk()
  initializeNavigation()

  imagesLoaded(document.querySelector('body'), function (instance) {
    setTimeout(setReady, 500)
  })
}

function setReady() {
  const body = document.querySelector('body')
  const fader = document.querySelector('#fader')

  body.classList.remove('unloaded')

  navigationReady()
  moonwalkReady()

  Velocity(
    fader,
    {
      opacity: 0
    },
    {
      duration: 1000,
      complete: () => {
        fader.style.display = 'none'
      }
    }
  )
}

let App = {}

export default App
