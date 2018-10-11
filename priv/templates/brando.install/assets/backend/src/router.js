import Vue from 'vue'
import Router from 'vue-router'
import kurtzBaseRoutes from 'kurtz/lib/routes/base'
import localRoutes from '@/routes'
import store from './store'

Vue.use(Router)

const allRoutes = [].concat(
  kurtzBaseRoutes,
  localRoutes
)

const router = new Router({
  base: 'admin',
  mode: 'history',
  linkActiveClass: 'active',
  routes: allRoutes
})

router.afterEach(route => {
  document.title = route.meta.title ? route.meta.title : 'SITE NAME'
})

router.beforeEach((to, from, next) => {
  const token = store.getters['users/token']
  // check if the user needs to be authenticated.
  // If yes, redirect to the login page if the token is null
  if (to.matched.some(m => m.meta.noAuth)) {
    next()
  } else {
    if (!token) {
      return router.replace({ name: 'login', query: { redirect: to.fullPath } })
    }
    next()
  }
})

export default router
