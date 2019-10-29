import apollo from '@univers-agency/kurtz/lib/api/apolloClient'
import { handleErr } from '@univers-agency/kurtz/lib/api/errorHandler.js'
// import { pick } from '@univers-agency/kurtz/lib/utils'

import <%= String.upcase(singular) %>_QUERY from './graphql/<%= vue_plural %>/<%= String.upcase(singular) %>_QUERY.graphql'
import <%= String.upcase(plural) %>_QUERY from './graphql/<%= vue_plural %>/<%= String.upcase(plural) %>_QUERY.graphql'
import CREATE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= vue_plural %>/CREATE_<%= String.upcase(singular) %>_MUTATION.graphql'
import UPDATE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= vue_plural %>/UPDATE_<%= String.upcase(singular) %>_MUTATION.graphql'
import DELETE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= vue_plural %>/DELETE_<%= String.upcase(singular) %>_MUTATION.graphql'

const <%= vue_singular %>API = {
  /**
   * get<%= Recase.to_pascal(vue_plural) %> - get all <%= vue_plural %>
   *
   * @return {Object}
   */
  async get<%= Recase.to_pascal(vue_plural) %> () {
    try {
      const result = await apollo.client.query({
        query: <%= String.upcase(plural) %>_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.<%= vue_plural %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * get<%= Recase.to_pascal(vue_singular) %> - get single <%= vue_singular %>
   *
   * @param  {Number}
   * @return {Object}
   */
  async get<%= Recase.to_pascal(vue_singular) %> (<%= vue_singular %>Id) {
    try {
      const result = await apollo.client.query({
        query: <%= String.upcase(singular) %>_QUERY,
        variables: {
          <%= vue_singular %>Id
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.<%= vue_singular %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * create<%= Recase.to_pascal(vue_singular) %> - Mutation for creating <%= vue_singular %>
   *
   * @param {Object} <%= vue_singular %>Params
   * @return {Object}
   */
  async create<%= Recase.to_pascal(vue_singular) %> (<%= vue_singular %>Params) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= vue_singular %>Params
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create<%= Recase.to_pascal(vue_singular) %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * update<%= Recase.to_pascal(vue_singular) %> - Mutation for updating <%= vue_singular %>
   *
   * @param {Object} <%= vue_singular %>Params
   * @return {Object}
   */
  async update<%= Recase.to_pascal(vue_singular) %> (<%= vue_singular %>Id, <%= vue_singular %>Params) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= vue_singular %>Id,
          <%= vue_singular %>Params
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update<%= Recase.to_pascal(vue_singular) %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * delete<%= Recase.to_pascal(vue_singular) %>
   *
   * @param {Number} <%= vue_singular %>Id
   * @return {Object}
   */
  async delete<%= Recase.to_pascal(vue_singular) %> (<%= vue_singular %>Id) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= vue_singular %>Id
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.delete<%= Recase.to_pascal(vue_singular) %>
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  <%= vue_singular %>API
}
