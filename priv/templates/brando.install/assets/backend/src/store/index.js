import { Vue, Vuex } from 'kurtz'
import * as kurtzBaseStoreModules from 'kurtz/lib/stores'

Vue.use(Vuex)

const debug = process.env.NODE_ENV !== 'production'

const store = new Vuex.Store({
  modules: {
    ...kurtzBaseStoreModules
  },
  strict: debug
})

// check if we have a token in localStorage and store it to vuex
const token = localStorage.getItem('token')
if (token) {
  store.commit('users/STORE_TOKEN', token)
}

export default store
