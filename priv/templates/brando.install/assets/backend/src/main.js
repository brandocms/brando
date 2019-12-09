import Vue from 'vue'
import VueBrando from 'brandojs'

import Admin from 'brandojs/src/Admin'
import router from 'brandojs/src/router'
import routes from './routes'
import menuSections from './menus'
import i18n from 'brandojs/src/i18n'
import app from './config'

Vue.use(VueBrando, { app, menuSections })

new Vue({
  router,
  i18n,
  render: h => h(Admin),
  created() {
    console.log('==> adding local routes')
    this.$router.addRoutes(routes)
  }
}).$mount('#app')
