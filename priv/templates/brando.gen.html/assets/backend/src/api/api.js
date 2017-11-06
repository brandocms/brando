import apollo from 'kurtz/lib/api/apolloClient'
import { handleErr } from 'kurtz/lib/api/errorHandler.js'
// import { pick } from 'kurtz/lib/utils'

import <%= String.upcase(singular) %>_QUERY from './graphql/<%= plural %>/<%= String.upcase(singular) %>_QUERY.graphql'
import <%= String.upcase(plural) %>_QUERY from './graphql/<%= plural %>/<%= String.upcase(plural) %>_QUERY.graphql'
import CREATE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= plural %>/CREATE_<%= String.upcase(singular) %>_MUTATION.graphql'
import UPDATE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= plural %>/UPDATE_<%= String.upcase(singular) %>_MUTATION.graphql'
import DELETE_<%= String.upcase(singular) %>_MUTATION from './graphql/<%= plural %>/DELETE_<%= String.upcase(singular) %>_MUTATION.graphql'

const <%= singular %>API = {
  /**
   * get<%= String.capitalize(plural) %> - get all <%= plural %>
   *
   * @return {Object}
   */
  async get<%= String.capitalize(plural) %> () {
    try {
      const result = await apollo.client.query({
        query: <%= String.upcase(plural) %>_QUERY,
        fetchPolicy: 'network-only'
      })
      return result.data.<%= plural %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * get<%= String.capitalize(singular) %> - get single <%= singular %>
   *
   * @param  {Number}
   * @return {Object}
   */
  async get<%= String.capitalize(singular) %> (<%= singular %>Id) {
    try {
      const result = await apollo.client.query({
        query: <%= String.upcase(singular) %>_QUERY,
        variables: {
          <%= singular %>Id
        },
        fetchPolicy: 'network-only'
      })
      return result.data.<%= singular %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * create<%= String.capitalize(singular) %> - Mutation for creating <%= singular %>
   *
   * @param {Object} <%= singular %>Params
   * @return {Object}
   */
  async create<%= String.capitalize(singular) %> (<%= singular %>Params) {
    try {
      const result = await apollo.<%= singular %>.mutate({
        mutation: CREATE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= singular %>Params
        },
        fetchPolicy: 'network-only'
      })
      return result.data.create_<%= singular %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * update<%= String.capitalize(singular) %> - Mutation for updating <%= singular %>
   *
   * @param {Object} <%= singular %>Params
   * @return {Object}
   */
  async update<%= String.capitalize(singular) %> (<%= singular %>Id, <%= singular %>Params) {
    try {
      const result = await apollo.<%= singular %>.mutate({
        mutation: UPDATE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= singular %>Id,
          <%= singular %>Params
        },
        fetchPolicy: 'network-only'
      })
      return result.data.update_<%= singular %>
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * delete<%= String.capitalize(singular) %>
   *
   * @param {Number} <%= singular %>Id
   * @return {Object}
   */
  async delete<%= String.capitalize(singular) %> (<%= singular %>Id) {
    try {
      const result = await apollo.<%= singular %>.mutate({
        mutation: DELETE_<%= String.upcase(singular) %>_MUTATION,
        variables: {
          <%= singular %>Id
        },
        fetchPolicy: 'network-only'
      })
      return result.data.delete_<%= singular %>
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  <%= singular %>API
}
