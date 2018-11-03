import Headroom from 'headroom.js'
import { TweenLite } from 'gsap/TweenMax'
import scrollIntoView from 'scroll-into-view-if-needed'

/**
 * Called at document ready
 */
export function initializeNavigation () {
  initializeMenu()
  initializeHeadroom()
  bindLinks()

  if (window.location.hash) {
    const header = document.querySelector('header')
    header.classList.add('headroom--unpinned')
  }
}

/**
 * Called right before page ready
 */
export function navigationReady () {
  checkHeadroom()
}

function initializeHeadroom () {
  var opts = {
    offset: 5,
    tolerance: {
      down: 0,
      up: 0
    },
    classes: {
      initial: 'animated'
    }
  }

  var headroom = new Headroom(document.querySelector('header'), opts)
  headroom.init()
}

function initializeMenu () {
  const hamburger = document.querySelector('.hamburger')
  hamburger.addEventListener('click', e => {
    toggleMenu()
  })
}

function bindLinks () {
  const fader = document.querySelector('#fader')
  const links = document.querySelectorAll('a:not([href^="#"]):not([target="_blank"]):not([data-lightbox])')
  const anchors = document.querySelectorAll('a[href^="#"]')
  let wait = false

  anchors.forEach(link => {
    link.addEventListener('click', function (e) {
      e.preventDefault()
      const href = this.getAttribute('href')

      if (document.body.classList.contains('open-menu')) {
        toggleMenuOff()
        wait = true
      }

      const move = () => {
        let dataID = href
        let dataTarget = document.querySelector(dataID)
        e.preventDefault()
        if (dataTarget) {
          scrollIntoView(dataTarget, { block: 'start', behavior: 'smooth' })
        }
      }

      if (wait) {
        setTimeout(move, 100)
      } else {
        move()
      }
    })
  })

  links.forEach(link => {
    link.addEventListener('click', e => {
      const loadingContainer = document.querySelector('.loading-container')
      const href = link.getAttribute('href')

      e.preventDefault()

      loadingContainer.style.display = 'none'

      if (href.indexOf(document.location.hostname) > -1 || href.startsWith('/')) {
        fader.style.display = 'block'
        TweenLite.to(fader, 0.350, {
          opacity: 1,
          onComplete: () => {
            window.location = href
          }
        })
      }
    })
  })
}

function checkHeadroom () {
  // If we are scrolled down on page load, add the pinned class
  let top = window.pageYOffset || document.documentElement.scrollTop
  if (top > 0) {
    document.querySelector('header').classList.remove('headroom--unpinned')
    document.querySelector('header').classList.add('headroom--pinned')
  }
}

function toggleMenu () {
  const body = document.querySelector('body')
  if (body.classList.contains('open-menu')) {
    toggleMenuOff()
  } else {
    toggleMenuOn()
  }
}

function toggleMenuOff () {
  const body = document.querySelector('body')
  const nav = document.querySelector('nav')
  const header = document.querySelector('header')
  const hamburger = document.querySelector('.hamburger')

  // CLOSING MENU
  hamburger.classList.toggle('is-active')
  TweenLite.to(nav, 0.350, {
    x: '100%',
    onComplete: () => {
      TweenLite.to(header, 0, {
        clearProps: 'backgroundColor,height',
        onComplete: () => {
          body.classList.toggle('open-menu')
          if (header.classList.contains('headroom--not-top')) {
            header.classList.add('headroom--pinned')
          }
        }
      })
    }
  })
}

function toggleMenuOn () {
  const body = document.querySelector('body')
  const nav = document.querySelector('nav')
  const header = document.querySelector('header')
  const hamburger = document.querySelector('.hamburger')

  // OPENING MENU
  nav.style.transform = 'translateX: 100%'

  TweenLite.to(header, 0, {
    backgroundColor: 'transparent',
    height: '100%',
    onComplete: () => {
      body.classList.toggle('open-menu')
      header.classList.remove('headroom--pinned')
      nav.style.opacity = 1
      hamburger.classList.toggle('is-active')
      TweenLite.to(nav, 0.350, { x: '0%' })
    }
  })
}
