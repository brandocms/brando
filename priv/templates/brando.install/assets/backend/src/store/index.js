// ++imports
import { Vue, Vuex } from '@univers-agency/kurtz'
import * as kurtzBaseStoreModules from '@univers-agency/kurtz/lib/stores'
// __imports

Vue.use(Vuex)

const debug = process.env.NODE_ENV !== 'production'

const store = new Vuex.Store({
  modules: {
    // ++content
    ...kurtzBaseStoreModules,
    // __content
  },
  strict: debug
})

// check if we have a token in localStorage and store it to vuex
const token = localStorage.getItem('token')
if (token) {
  store.commit('users/STORE_TOKEN', token)
}

export default store
