import '../css/app.css'
import '@brandocms/brandojs/css/app.css'

import { buildApplication } from '@brandocms/brandojs'

// Add your custom hooks here
const hooks = {}

// Build Brando application
const app = buildApplication(hooks)

// trigger ready state
if (document.attachEvent ? document.readyState === 'complete' : document.readyState !== 'loading') {
  app.initialize()
} else {
  document.addEventListener('DOMContentLoaded', app.initialize.apply(app))
}