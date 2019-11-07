import apollo from './apolloClient'
import { handleErr } from './errorHandler.js'
import { pick } from '../utils'

import IMAGE_SERIES_QUERY from './graphql/images/IMAGE_SERIES_QUERY.graphql'
import IMAGE_CATEGORY_QUERY from './graphql/images/IMAGE_CATEGORY_QUERY.graphql'
import IMAGE_CATEGORIES_QUERY from './graphql/images/IMAGE_CATEGORIES_QUERY.graphql'
import CREATE_IMAGE_SERIES_MUTATION from './graphql/images/CREATE_IMAGE_SERIES_MUTATION.graphql'
import CREATE_IMAGE_CATEGORY_MUTATION from './graphql/images/CREATE_IMAGE_CATEGORY_MUTATION.graphql'
import UPDATE_IMAGE_SERIES_MUTATION from './graphql/images/UPDATE_IMAGE_SERIES_MUTATION.graphql'
import UPDATE_IMAGE_CATEGORY_MUTATION from './graphql/images/UPDATE_IMAGE_CATEGORY_MUTATION.graphql'
import DELETE_IMAGE_SERIES_MUTATION from './graphql/images/DELETE_IMAGE_SERIES_MUTATION.graphql'
import DELETE_IMAGE_CATEGORY_MUTATION from './graphql/images/DELETE_IMAGE_CATEGORY_MUTATION.graphql'
import DUPLICATE_IMAGE_CATEGORY_MUTATION from './graphql/images/DUPLICATE_IMAGE_CATEGORY_MUTATION.graphql'

export const imageAPI = {
  /**
   * getImageCategory
   *
   * @param {Number} categoryId
   * @return {Object}
   */
  async getImageCategory (categoryId, queryVars) {
    try {
      const result = await apollo.client.query({
        query: IMAGE_CATEGORY_QUERY,
        variables: {
          categoryId,
          ...queryVars
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.image_category
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getImageCategories - get all image categories
   *
   * @return {Object}
   */
  async getImageCategories () {
    try {
      const result = await apollo.client.query({
        query: IMAGE_CATEGORIES_QUERY,
        fetchPolicy: 'no-cache'
      })
      return result.data.image_categories
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * getImageSeries - get specific image series
   *
   * @param {Number} seriesId
   * @return {Object}
   */
  async getImageSeries (seriesId) {
    try {
      const result = await apollo.client.query({
        query: IMAGE_SERIES_QUERY,
        variables: {
          seriesId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.image_series
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createImageSeries - Mutation for creating image series
   *
   * @param {Object} imageSeries
   * @return {Object}
   */
  async createImageSeries (imageSeries) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_IMAGE_SERIES_MUTATION,
        variables: {
          image_series_params: pick(imageSeries, 'name', 'credits', 'image_category_id')
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create_image_series
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * createImageCategory - Mutation for creating image category
   *
   * @param {Object} imageCategory
   * @return {Object}
   */
  async createImageCategory (imageCategory) {
    try {
      const result = await apollo.client.mutate({
        mutation: CREATE_IMAGE_CATEGORY_MUTATION,
        variables: {
          image_category_params: pick(imageCategory, 'name', 'credits')
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.create_image_category
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updateImageCategory
   *
   * @param {Number} imageCategoryId
   * @param {Object} imageCategoryParams
   * @return {Object}
   */
  async updateImageCategory (imageCategoryId, imageCategoryParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_IMAGE_CATEGORY_MUTATION,
        variables: {
          image_category_id: imageCategoryId,
          image_category_params: pick(imageCategoryParams, 'name', 'credits')
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update_image_category
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * updateImageSeries
   *
   * @param {Number} imageSeriesId
   * @param {Object} imageSeriesParams
   * @return {Object}
   */
  async updateImageSeries (imageSeriesId, imageSeriesParams) {
    try {
      const result = await apollo.client.mutate({
        mutation: UPDATE_IMAGE_SERIES_MUTATION,
        variables: {
          image_series_id: imageSeriesId,
          image_series_params: pick(imageSeriesParams, 'name', 'credits')
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.update_image_series
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deleteImageSeries
   *
   * @param {Number} imageSeriesId
   * @return {Object}
   */
  async deleteImageSeries (imageSeriesId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_IMAGE_SERIES_MUTATION,
        variables: {
          image_series_id: imageSeriesId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.delete_image_series
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * deleteImageCategory
   *
   * @param {Number} imageCategoryId
   * @return {Object}
   */
  async deleteImageCategory (imageCategoryId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DELETE_IMAGE_CATEGORY_MUTATION,
        variables: {
          image_category_id: imageCategoryId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.delete_image_category
    } catch (err) {
      handleErr(err)
    }
  },

  /**
   * duplicateImageCategory
   *
   * @param {Number} imageCategoryId
   * @return {Object}
   */
  async duplicateImageCategory (imageCategoryId) {
    try {
      const result = await apollo.client.mutate({
        mutation: DUPLICATE_IMAGE_CATEGORY_MUTATION,
        variables: {
          image_category_id: imageCategoryId
        },
        fetchPolicy: 'no-cache'
      })
      return result.data.duplicate_image_category
    } catch (err) {
      handleErr(err)
    }
  }
}
