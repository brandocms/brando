import nprogress from 'nprogress'

const STORE_<%= String.upcase(singular) %> = 'STORE_<%= String.upcase(singular) %>'
const STORE_<%= String.upcase(plural) %> = 'STORE_<%= String.upcase(plural) %>'
const DELETE_<%= String.upcase(singular) %> = 'DELETE_<%= String.upcase(singular) %>'

import { <%= vue_singular %>API } from '../../api/<%= vue_singular %>'

export const <%= vue_plural %> = {
  namespaced: true,
  // initial state
  state: {
    <%= vue_singular %>: {},
    <%= vue_plural %>: []
  },

  // mutations
  mutations: {
    [DELETE_<%= String.upcase(singular) %>] (state, <%= vue_singular %>) {
      const pIdx = state.<%= vue_plural %>.indexOf(<%= vue_singular %>)

      state.<%= vue_plural %> = [
        ...state.<%= vue_plural %>.slice(0, pIdx),
        ...state.<%= vue_plural %>.slice(pIdx + 1)
      ]
    },

    [STORE_<%= String.upcase(singular) %>] (state, <%= vue_singular %>) {
      state.<%= vue_singular %> = <%= vue_singular %>
    },

    [STORE_<%= String.upcase(plural) %>] (state, <%= vue_plural %>) {
      state.<%= vue_plural %> = <%= vue_plural %>
    }
  },

  getters: {
    all<%= Recase.to_pascal(vue_plural) %>: state => {
      return state.<%= vue_plural %>
    }
  },

  actions: {
    async get<%= Recase.to_pascal(vue_plural) %> (context, variables) {
      nprogress.start()
      const <%= vue_plural %> = await <%= vue_singular %>API.get<%= Recase.to_pascal(vue_plural) %>(variables)
      context.commit(STORE_<%= String.upcase(plural) %>, <%= vue_plural %>)
      nprogress.done()
      return <%= vue_plural %>
    },

    async get<%= Recase.to_pascal(vue_singular) %> (context, <%= vue_singular %>Id) {
      nprogress.start()
      const <%= vue_singular %> = await <%= vue_singular %>API.get<%= Recase.to_pascal(vue_singular) %>(<%= vue_singular %>Id)
      context.commit(STORE_<%= String.upcase(singular) %>, <%= vue_singular %>)
      nprogress.done()
      return <%= vue_singular %>
    },

    async delete<%= Recase.to_pascal(vue_singular) %> (context, <%= vue_singular %>) {
      nprogress.start()
      await <%= vue_singular %>API.delete<%= Recase.to_pascal(vue_singular) %>(<%= vue_singular %>.id)
      context.commit(DELETE_<%= String.upcase(singular) %>, <%= vue_singular %>)
      nprogress.done()
      return <%= vue_singular %>
    }
  }
}
