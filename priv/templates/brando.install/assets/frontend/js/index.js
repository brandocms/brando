/**
 * BRANDO APPLICATION FRONTEND
 * (c) 2021
 */

/**
 * JUPITER IMPORTS
 */
import {
  Application,
  Cookies,
  Events,
  Links,
  MobileMenu,
  Moonwalk,
  FixedHeader,
  gsap
} from '@brandocms/jupiter'

/**
 * APP SPECIFIC MODULE IMPORTS
 */

/**
 * CONFIG IMPORTS
 */
import configureBreakpoints from './config/BREAKPOINTS'
import configureHeader from './config/HEADER'
import configureMobileMenu from './config/MOBILE_MENU'
import configureMoonwalk from './config/MOONWALK'

import '../css/app.css'

const app = new Application({
  breakpointConfig: configureBreakpoints,
  faderOpts: {
    fadeIn: (callback) => {
        callback()
    }
  }
})

app.registerCallback(Events.APPLICATION_READY, () => {
  app.links = new Links(app)
})

app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
  app.moonwalk = new Moonwalk(app, configureMoonwalk(app))
  app.header = new FixedHeader(app, configureHeader(app))
  app.mobileMenu = new MobileMenu(app, configureMobileMenu(app))
  app.cookies = new Cookies(app)
})

app.registerCallback(Events.APPLICATION_REVEALED, () => {
  // called after Application is finished revealing
})

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
