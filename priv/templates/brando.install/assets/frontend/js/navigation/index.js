// import Headroom from 'headroom.js'
import { TweenLite, Power3, Sine } from 'gsap/TweenMax'
import scrollIntoView from 'scroll-into-view-if-needed'
import FixedHeader from '../fixedHeader/'

/**
 * Called at document ready
 */
export function initializeNavigation() {
  if (document.body.getAttribute('data-script') === 'licenses') {
    return
  }

  const logo = document.querySelector('.navbar-brand')
  const logoText = document.querySelector('.navbar-brand .logo-text')

  const header = new FixedHeader(
    document.querySelector('header'),
    {
      regBgColor: '#ffffff',
      onPin: (h) => {
        TweenLite.to(
          h.el,
          0.5,
          {
            yPercent: '0',
            ease: Sine.easeOut,
            force3D: true
          }
        )
      },

      onUnpin: (h) => {
        TweenLite.to(
          h.el,
          0.5,
          {
            yPercent: '-100',
            ease: Sine.easeIn,
            force3D: true
          }
        )
      },

      onSmall: () => {
      },
      onNotSmall: () => {
      },

      onAltBg: (h) => {
        TweenLite.to(
          h.el,
          0.2,
          {
            backgroundColor: h.altBgColor
          }
        )
      },

      onNotAltBg: (h) => {
        TweenLite.to(
          h.el,
          0.4,
          {
            backgroundColor: h.regBgColor
          }
        )
      }
    }
  )
  header.initialize()
  initializeMenu()
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

}

function initializeMenu () {
  const hamburger = document.querySelector('.hamburger')
  hamburger.addEventListener('click', e => {
    toggleMenu()
  })
}

function bindLinks () {
  const fader = document.querySelector('#fader')
  const links = document.querySelectorAll('a:not([href^="#"]):not([target="_blank"]):not([data-lightbox]):not(.plain)')
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
        let main = document.querySelector('main')
        fader.style.display = 'block'
        TweenLite.to(main, 0.8, {
          yPercent: 3,
          ease: Power3.easeOut
        })

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
