import apollo from './apolloClient'
import { handleErr } from './errorHandler.js'
import { pick } from '../utils'

import PAGE_QUERY from './graphql/pages/PAGE_QUERY.graphql'
import PAGES_QUERY from './graphql/pages/PAGES_QUERY.graphql'
import CREATE_PAGE_MUTATION from './graphql/pages/CREATE_PAGE_MUTATION.graphql'
import UPDATE_PAGE_MUTATION from './graphql/pages/UPDATE_PAGE_MUTATION.graphql'
import DELETE_PAGE_MUTATION from './graphql/pages/DELETE_PAGE_MUTATION.graphql'

const pageAPI = {
  /**
   * getPages - get all pages
   *
   * @return {Object}
   */
  async getPages () {
    try {
      const result = await apollo.client.query({
        query: PAGES_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.pages
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getPage - get specific page by id
   *
   * @param {Number} pageId
   * @return {Object}
   */
  async getPage (pageId) {
    try {
      const result = await apollo.client.query({
        query: PAGE_QUERY,
        variables: {
          pageId: pageId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.page
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createPage - Mutation for creating page
   *
   * @param {Object} pageParams
   * @return {Object}
   */
  async createPage (pageParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_PAGE_MUTATION,
        variables: {
          pageParams: pick(
            pageParams,
            'parent_id',
            'key',
            'language',
            'title',
            'data',
            'status',
            'css_classes',
            'meta_description'
          )
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create_page
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updatePage - Mutation for updating page
   *
   * @param {Number} pageId
   * @param {Object} pageParams
   * @return {Object}
   */
  async updatePage (pageId, pageParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_PAGE_MUTATION,
        variables: {
          pageId: pageId,
          pageParams: pick(
            pageParams,
            'parent_id',
            'key',
            'language',
            'title',
            'data',
            'status',
            'css_classes',
            'meta_description'
          )
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update_page
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deletePage - Mutation for deleting page
   *
   * @param {Number} pageId
   * @return {Object}
   */
  async deletePage (pageId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_PAGE_MUTATION,
        variables: {
          page_id: pageId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.delete_page
    } catch (err) {
      handleErr(err)
    }
  }
}

export {
  pageAPI
}
