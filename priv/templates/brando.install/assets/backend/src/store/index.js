// ++imports
import { Vue, Vuex } from 'brandojs'
import * as kurtzBaseStoreModules from 'brandojs/lib/stores'
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
