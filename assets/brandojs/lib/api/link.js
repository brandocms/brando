import apollo from 'brandojs/lib/api/apolloClient'
import { handleErr } from 'brandojs/lib/api/errorHandler.js'
// import { pick } from 'brandojs/lib/utils'

import LINK_QUERY from './graphql/links/LINK_QUERY.graphql'
import LINKS_QUERY from './graphql/links/LINKS_QUERY.graphql'
import CREATE_LINK_MUTATION from './graphql/links/CREATE_LINK_MUTATION.graphql'
import UPDATE_LINK_MUTATION from './graphql/links/UPDATE_LINK_MUTATION.graphql'
import DELETE_LINK_MUTATION from './graphql/links/DELETE_LINK_MUTATION.graphql'

const linkAPI = {
  /**
   * getLinks - get all links
   *
   * @return {Object}
   */
  async getLinks () {
    try {
      const result = await apollo.client.query({
        query: LINKS_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.links
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getLink - get single link
   *
   * @param  {Number}
   * @return {Object}
   */
  async getLink (linkId) {
    try {
      const result = await apollo.client.query({
        query: LINK_QUERY,
        variables: {
          linkId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.link
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createLink - Mutation for creating link
   *
   * @param {Object} linkParams
   * @return {Object}
   */
  async createLink (linkParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_LINK_MUTATION,
        variables: {
          linkParams
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.createLink
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updateLink - Mutation for updating link
   *
   * @param {Object} linkParams
   * @return {Object}
   */
  async updateLink (linkId, linkParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_LINK_MUTATION,
        variables: {
          linkId,
          linkParams
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.updateLink
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deleteLink
   *
   * @param {Number} linkId
   * @return {Object}
   */
  async deleteLink (linkId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_LINK_MUTATION,
        variables: {
          linkId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.deleteLink
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  linkAPI
}
