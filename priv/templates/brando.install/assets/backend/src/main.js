import '@/styles/app.scss'
import { Vue } from '@univers-agency/kurtz'

import { installMenus } from './menus'
import { installConfig, installKurtz } from '@univers-agency/kurtz/lib/install'

import App from '@univers-agency/kurtz/lib/views/App.vue'
import store from '@/store'
import router from '@/router'

import SITE_CONFIG from './config'

// Install Kurtz
installKurtz(Vue)

// Install local menus
installMenus(store)

// Install configuration
installConfig(store, SITE_CONFIG)

// Create application Vue instance
const app = new Vue({
  router,
  store,
  ...App
})

// Mount application
app.$mount('#app')

export {
  app,
  router,
  store
}
