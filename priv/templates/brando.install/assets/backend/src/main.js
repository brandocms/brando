import '../css/app.css'

import { Events } from '@brandocms/jupiter'
import { buildApplication, brandoHooks, initializeLiveSocket } from '@brandocms/brandojs'

// Build Brando application
const app = buildApplication()

// Add your custom hooks here
const hooks = {}

app.registerCallback(Events.APPLICATION_READY, () => initializeLiveSocket({...hooks, ...brandoHooks(app)}))

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}