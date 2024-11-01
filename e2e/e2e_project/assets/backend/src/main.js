import '../css/app.css'
import '@brandocms/brandojs/css/app.css'

import { buildApplication } from '@brandocms/brandojs'

// Add your custom hooks here
const hooks = {}
const ENABLE_DEBUG = true

// Build Brando application
const app = buildApplication(hooks, ENABLE_DEBUG)

// trigger ready state
if (
  document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading'
) {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}
