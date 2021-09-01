// CSS imports
import '../css/auth.css'

import { Application, Events, Moonwalk, gsap } from '@brandocms/jupiter'
import configureBreakpoints from './config/BREAKPOINTS'

const MOONWALK_CONFIG = {
  rootMargin: '0% 0% -10% 0%',
  threshold: 0,
  initialDelay: 100,

  runs: {
    brandoLogin: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        gsap.set(['.field-wrapper', '.brando-versioning', '.login-box', '.primary', '.figure-wrapper', '.title'], { opacity: 0 })
        gsap.set('.login-box', { y: 35 })
        gsap.set(['.field-wrapper', '.primary', '.title'], { x: -15 })
        gsap.set('.figure-wrapper', { x: -10 })
        gsap.set('.brando-versioning', { xPercent: -200 })

        timeline
          .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
          .to('.login-box', { y: 0, duration: 0.5, ease: 'power3.out' })
          .to('.login-box', { opacity: 1, duration: 0.5, ease: 'none' }, '<')
          .to(['.title', '.field-wrapper', '.primary'], { x: 0, duration: 0.35, ease: 'circ.out', stagger: 0.1 }, '<0.25')
          .to(['.title', '.field-wrapper', '.primary'], { opacity: 1, duration: 0.35, ease: 'none', stagger: 0.1 }, '<')
          .to('.figure-wrapper', { x: 0, duration: 0.35, ease: 'circ.out' }, '<')
          .to('.figure-wrapper', { opacity: 1, duration: 0.35, ease: 'none' }, '<')
          .to('.brando-versioning', { opacity: 1, ease: 'none' })
          .to('.brando-versioning', { xPercent: 0, ease: 'circ.out' })
      }
    }
  }
}

const app = new Application({
  breakpointConfig: configureBreakpoints(),
  faderOpts: {
    fadeIn: callback => {
      gsap.set('.fader', { display: 'none' })
      document.body.classList.remove('unloaded')
      callback()
    }
  }
})

app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
  app.moonwalk = new Moonwalk(app, MOONWALK_CONFIG)
})

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}