import '@/styles/app.scss'
import { Vue } from 'kurtz'

import { installMenus } from './menus'
import { installConfig, installKurtz } from 'kurtz/lib/install'

import App from 'kurtz/lib/views/App.vue'
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
