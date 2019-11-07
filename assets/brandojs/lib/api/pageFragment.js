import apollo from './apolloClient'
import { handleErr } from './errorHandler.js'
import { pick } from '../utils'

import PAGE_FRAGMENT_QUERY from './graphql/pageFragments/PAGE_FRAGMENT_QUERY.graphql'
import PAGE_FRAGMENTS_QUERY from './graphql/pageFragments/PAGE_FRAGMENTS_QUERY.graphql'
import CREATE_PAGE_FRAGMENT_MUTATION from './graphql/pageFragments/CREATE_PAGE_FRAGMENT_MUTATION.graphql'
import UPDATE_PAGE_FRAGMENT_MUTATION from './graphql/pageFragments/UPDATE_PAGE_FRAGMENT_MUTATION.graphql'
import DELETE_PAGE_FRAGMENT_MUTATION from './graphql/pageFragments/DELETE_PAGE_FRAGMENT_MUTATION.graphql'

const pageFragmentAPI = {
  /**
   * getPageFragments - get all pageFragments
   *
   * @return {Object}
   */
  async getPageFragments () {
    try {
      const result = await apollo.client.query({
        query: PAGE_FRAGMENTS_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.page_fragments
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getPageFragment - get specific pageFragment by id
   *
   * @param {Number} pageFragmentId
   * @return {Object}
   */
  async getPageFragment (pageFragmentId) {
    try {
      const result = await apollo.client.query({
        query: PAGE_FRAGMENT_QUERY,
        variables: {
          pageFragmentId: pageFragmentId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.page_fragment
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createPageFragment - Mutation for creating pageFragment
   *
   * @param {Object} pageFragmentParams
   * @return {Object}
   */
  async createPageFragment (pageFragmentParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_PAGE_FRAGMENT_MUTATION,
        variables: {
          pageFragmentParams: pick(
            pageFragmentParams,
            'parent_key',
            'key',
            'language',
            'wrapper',
            'data',
            'page_id'
          )
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create_page_fragment
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updatePageFragment - Mutation for updating pageFragment
   *
   * @param {Number} pageFragmentId
   * @param {Object} pageFragmentParams
   * @return {Object}
   */
  async updatePageFragment (pageFragmentId, pageFragmentParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_PAGE_FRAGMENT_MUTATION,
        variables: {
          pageFragmentId: pageFragmentId,
          pageFragmentParams: pick(
            pageFragmentParams,
            'parent_key',
            'key',
            'language',
            'data',
            'wrapper',
            'page_id'
          )
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update_page_fragment
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deletePageFragment - Mutation for deleting pageFragment
   *
   * @param {Number} pageFragmentId
   * @return {Object}
   */
  async deletePageFragment (pageFragmentId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_PAGE_FRAGMENT_MUTATION,
        variables: {
          pageFragmentId: pageFragmentId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.delete_page_fragment
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  pageFragmentAPI
}
