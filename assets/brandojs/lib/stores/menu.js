import {
  STORE_MENU,
  TOGGLE_MENU
} from './mutation-types'

export const menu = {
  namespaced: true,
  // initial state
  state: {
    entries: [],
    status: false
  },

  // mutations
  mutations: {
    [STORE_MENU] (state, entry) {
      state.entries = [].concat(...state.entries, entry)
    },

    [TOGGLE_MENU] (state) {
      state.status = !state.status
    }
  },

  getters: {
    entries: state => {
      return state.entries
    },

    status: state => {
      return state.status
    }
  }
}
