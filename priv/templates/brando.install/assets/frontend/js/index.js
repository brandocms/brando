/**
 * UNIVERS/TWINED APPLICATION FRONTEND
 * (c) 2020 UNIVERS/TWINED TM
 */

/**
 * JUPITER IMPORTS
 */
import {
  Application,
  Cookies,
  Events,
  Lazyload,
  Lightbox,
  Links,
  MobileMenu,
  Moonwalk,
  Popup,
  StackedBoxes,
  FixedHeader
} from '@univers-agency/jupiter'

/**
 * APP SPECIFIC MODULE IMPORTS
 */

/**
 * CONFIG IMPORTS
 */
import configureBreakpoints from './config/BREAKPOINTS'
import configureHeader from './config/HEADER'
import configureLightbox from './config/LIGHTBOX'
import configureMobileMenu from './config/MOBILE_MENU'
import configureMoonwalk from './config/MOONWALK'


import '../css/app.pcss'

const app = new Application({
  breakpointConfig: configureBreakpoints
})

app.registerCallback(Events.APPLICATION_READY, () => {
  app.links = new Links(app)
})

app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
  app.lightbox = new Lightbox(app, configureLightbox(app))
  app.lazyload = new Lazyload(app, { useNativeLazyloadIfAvailable: false })
  app.moonwalk = new Moonwalk(app, configureMoonwalk(app))
  app.header = new FixedHeader(app, configureHeader(app))
  app.mobileMenu = new MobileMenu(app, configureMobileMenu(app))
  app.cookies = new Cookies(app)
})

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
