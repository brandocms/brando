import Headroom from 'headroom.js'
import Velocity from 'velocity-animate'

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
          Velocity(dataTarget, 'scroll', {
            // duration: 1500,
            easing: 'ease-in-out'
          })
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

        Velocity(
          fader,
          {
            opacity: 1
          },
          {
            duration: 350,
            complete: (elements) => {
              window.location = href
            }
          }
        )
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
  Velocity(nav, {
    // opacity: 0,
    translateX: '100%'
  }, {
    duration: 350,
    complete: () => {
      header.style.height = 'auto'
      body.classList.toggle('open-menu')
      if (header.classList.contains('headroom--not-top')) {
        header.classList.add('headroom--pinned')
      }
    }
  })
}

function toggleMenuOn () {
  const body = document.querySelector('body')
  const nav = document.querySelector('nav')
  const header = document.querySelector('header')
  const hamburger = document.querySelector('.hamburger')

  // OPENING MENU
  header.classList.remove('headroom--pinned')
  nav.style.position = 'fixed'
  Velocity(nav, { translateX: '100%' }, { duration: 0, queue: false })
  Velocity(header, { height: '100%' }, {
    duration: 0,
    queue: false,
    complete: () => {
      nav.style.opacity = 1
      hamburger.classList.toggle('is-active')
      body.classList.toggle('open-menu')
      Velocity(nav, { translateX: '0%' }, { duration: 350 })
    }
  })
}
