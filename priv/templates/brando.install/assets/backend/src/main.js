import Vue from 'vue'
import VueBrando from 'brandojs'

import Admin from 'brandojs/src/Admin'
import router from 'brandojs/src/router'
import routes from './routes'
import menuSections from './menus'
import i18n from 'brandojs/src/i18n'
import app from './config'

import './styles/blocks.pcss'

Vue.use(VueBrando, { app, menuSections })

new Vue({
  router,
  i18n,
  data: { ready: false },
  created() {
    routes.forEach(r => this.$router.addRoute(r))
  },
  render: h => h(Admin)
}).$mount('#app')
