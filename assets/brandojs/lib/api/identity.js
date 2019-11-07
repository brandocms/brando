import apollo from 'brandojs/lib/api/apolloClient'
import { handleErr } from 'brandojs/lib/api/errorHandler.js'

import IDENTITY_QUERY from './graphql/identities/IDENTITY_QUERY.graphql'
import UPDATE_IDENTITY_MUTATION from './graphql/identities/UPDATE_IDENTITY_MUTATION.graphql'
import DELETE_IDENTITY_MUTATION from './graphql/identities/DELETE_IDENTITY_MUTATION.graphql'

const identityAPI = {
  /**
   * getIdentity - get single identity
   *
   * @return {Object}
   */
  async getIdentity () {
    try {
      const result = await apollo.client.query({
        query: IDENTITY_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.identity
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updateIdentity - Mutation for updating identity
   *
   * @param {Object} identityParams
   * @return {Object}
   */
  async updateIdentity (identityParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_IDENTITY_MUTATION,
        variables: {
          identityParams
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.updateIdentity
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deleteIdentity
   *
   * @param {Number} identityId
   * @return {Object}
   */
  async deleteIdentity (identityId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_IDENTITY_MUTATION,
        variables: {
          identityId: identityId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.deleteIdentity
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  identityAPI
}
