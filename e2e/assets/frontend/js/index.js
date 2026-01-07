/**
 * BRANDO APPLICATION FRONTEND
 * (c) 2022
 */

/**
 * JUPITER IMPORTS
 */
import {
  Application,
  Cookies,
  Dom,
  Events,
  Lazyload,
  Links,
  MobileMenu,
  Moonwalk,
  FixedHeader,
  Typography,
} from '@brandocms/jupiter'

/**
 * APP SPECIFIC MODULE IMPORTS
 */

import SmartVideo from './modules/SmarterVideo'

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
      document.body.classList.remove('unloaded')
      callback()
    },
  },
})

app.registerCallback(Events.APPLICATION_READY, () => {
  app.links = new Links(app)
  app.lazyload = new Lazyload(app, { useNativeLazyloadIfAvailable: false })

  app.smartVideos = []

  Dom.all('[data-smart-video]').forEach((v) => {
    const video = new SmartVideo(app, v)
    app.smartVideos.push(video)
  })
})

app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
  app.moonwalk = new Moonwalk(app, configureMoonwalk(app))
  app.header = new FixedHeader(app, configureHeader(app))
  app.mobileMenu = new MobileMenu(app, configureMobileMenu(app))
  app.cookies = new Cookies(app)
  app.typo = new Typography()
})

app.registerCallback(Events.APPLICATION_REVEALED, () => {
  // called after Application is finished revealing
})

// trigger ready state
if (
  document.attachEvent
    ? document.readyState === 'complete'
    : document.readyState !== 'loading'
) {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
