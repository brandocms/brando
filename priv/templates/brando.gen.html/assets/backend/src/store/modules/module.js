import nprogress from 'nprogress'

const STORE_<%= String.upcase(@singular) %> = 'STORE_<%= String.upcase(@singular) %>'
const STORE_<%= String.upcase(@plural) %> = 'STORE_<%= String.upcase(@plural) %>'
const DELETE_<%= String.upcase(@singular) %> = 'DELETE_<%= String.upcase(@singular) %>'

import { <%= @singular %>API } from '../../api/<%= @singular %>'

export const <%= @plural %> = {
  namespaced: true,
  // initial state
  state: {
    <%= @singular %>: {},
    <%= @plural %>: []
  },

  // mutations
  mutations: {
    [DELETE_<%= String.upcase(@singular) %>] (state, <%= @singular %>Id) {
      const p = state.<%= @plural %>.find(p => parseInt(p.id) === parseInt(<%= @singular %>Id))
      const pIdx = state.<%= @plural %>.indexOf(p)

      state.<%= @plural %> = [
        ...state.<%= @plural %>.slice(0, pIdx),
        ...state.<%= @plural %>.slice(pIdx + 1)
      ]
    },

    [STORE_<%= String.upcase(@singular) %>] (state, <%= @singular %>) {
      state.<%= @singular %> = <%= @singular %>
    },

    [STORE_<%= String.upcase(@plural) %>] (state, <%= @plural %>) {
      state.<%= @plural %> = <%= @plural %>
    }
  },

  getters: {
    all<%= String.capitalize(@singular) %>s: state => {
      return state.<%= @plural %>
    }
  },

  actions: {
    async get<%= String.capitalize(@plural) %> (context, variables) {
      nprogress.start()
      const <%= @plural %> = await <%= @singular %>API.get<%= String.capitalize(@plural) %>(variables)
      context.commit(STORE_<%= String.upcase(@plural) %>, <%= @plural %>)
      nprogress.done()
      return <%= @plural %>
    },

    async get<%= String.capitalize(@singular) %> (context, <%= @singular %>Id) {
      nprogress.start()
      const <%= @singular %> = await <%= @singular %>API.get<%= String.capitalize(@singular) %>(<%= @singular %>Id)
      context.commit(STORE_<%= String.upcase(@singular) %>, <%= @singular %>)
      nprogress.done()
      return <%= @singular %>
    }
  }
}
