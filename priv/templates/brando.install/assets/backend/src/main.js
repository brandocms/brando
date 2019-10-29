import 'babel-polyfill'
import '@/styles/app.scss'
import Vue from 'vue'

// import Raven from 'raven-js'
// import RavenVue from 'raven-js/plugins/vue

import { installMenus } from './menus'
import { installConfig, installKurtz } from 'kurtz/lib/install'

import App from 'kurtz/lib/views/App.vue'
import store from '@/store'
import router from '@/router'
import { sync } from 'vuex-router-sync'

import SITE_CONFIG from './config'

// Install Kurtz
installKurtz(Vue)

// Install local menus
installMenus(store)

// Install configuration
installConfig(store, SITE_CONFIG)

// Sync router with store
sync(store, router)

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
