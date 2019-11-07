import nprogress from 'nprogress'
import {
  ADD_IMAGE_CATEGORY,
  ADD_IMAGE_SERIES,
  STORE_IMAGE,
  STORE_IMAGE_CATEGORY,
  STORE_IMAGE_CATEGORIES,
  DELETE_IMAGE,
  DELETE_IMAGE_SERIES,
  DELETE_IMAGE_CATEGORY,
  UPDATE_IMAGE_SERIES_SORT_ORDER
} from './mutation-types'

import { imageAPI } from '../api/image'

export const images = {
  namespaced: true,
  // initial state
  state: {
    imageCategories: [],
    imageCategory: {}
  },

  // mutations
  mutations: {
    [STORE_IMAGE_CATEGORIES] (state, imageCategories) {
      state.imageCategories = imageCategories
    },

    [STORE_IMAGE_CATEGORY] (state, imageCategory) {
      state.imageCategory = imageCategory
    },

    [STORE_IMAGE] (state, image) {
      // first we find the series
      const s = state.imageCategory.image_series.find(s => parseInt(s.id) === parseInt(image.image_series_id))
      if (!s) {
        console.error('ERROR: image_series not found E005', image, state.imageCategory.image_series)
        return
      }
      const idx = state.imageCategory.image_series.indexOf(s)

      const updatedSeries = {
        ...s,
        images: [
          ...s.images,
          image
        ]
      }

      state.imageCategory = {
        ...state.imageCategory,
        image_series: [
          ...state.imageCategory.image_series.slice(0, idx),
          updatedSeries,
          ...state.imageCategory.image_series.slice(idx + 1)
        ]
      }
    },

    // ADD = PUSH TO EXISTING ARRAY

    [ADD_IMAGE_SERIES] (state, imageSeries) {
      state.imageCategory = {
        ...state.imageCategory,
        image_series: [imageSeries, ...state.imageCategory.image_series]
      }
    },

    [ADD_IMAGE_CATEGORY] (state, imageCategory) {
      state.imageCategories = [...state.imageCategories, imageCategory]
    },

    [UPDATE_IMAGE_SERIES_SORT_ORDER] (state, { imageSeries, ids }) {
      const s = state.imageCategory.image_series.find(s => parseInt(s.id) === parseInt(imageSeries.id))
      const idx = state.imageCategory.image_series.indexOf(s)

      let sortedImageSeries = { ...s }

      for (let i = 0; i < ids.length; i++) {
        let imageId = ids[i]
        const img = sortedImageSeries.images.find(i => parseInt(i.id) === parseInt(imageId))
        const imgIdx = sortedImageSeries.images.indexOf(img)
        sortedImageSeries = {
          ...sortedImageSeries,
          images: [
            ...sortedImageSeries.images.slice(0, imgIdx),
            { ...img, sequence: i },
            ...sortedImageSeries.images.slice(imgIdx + 1)
          ]
        }
      }

      state.imageCategory = {
        ...state.imageCategory,
        image_series: [
          ...state.imageCategory.image_series.slice(0, idx),
          sortedImageSeries,
          ...state.imageCategory.image_series.slice(idx + 1)
        ]
      }
    },

    [DELETE_IMAGE] (state, { id, imageSeriesId }) {
      // first we find the series
      const s = state.imageCategory.image_series.find(s => parseInt(s.id) === parseInt(imageSeriesId))
      const idx = state.imageCategory.image_series.indexOf(s)

      const img = s.images.find(i => i.id === id)
      const imgIdx = s.images.indexOf(img)

      const updatedSeries = {
        ...s,
        images: [
          ...s.images.slice(0, imgIdx),
          ...s.images.slice(imgIdx + 1)
        ]
      }

      state.imageCategory = {
        ...state.imageCategory,
        image_series: [
          ...state.imageCategory.image_series.slice(0, idx),
          updatedSeries,
          ...state.imageCategory.image_series.slice(idx + 1)
        ]
      }
    },

    [DELETE_IMAGE_SERIES] (state, imageSeries) {
      const idx = state.imageCategory.image_series.indexOf(imageSeries)

      state.imageCategory = {
        ...state.imageCategory,
        image_series: [
          ...state.imageCategory.image_series.slice(0, idx),
          ...state.imageCategory.image_series.slice(idx + 1)
        ]
      }
    },

    [DELETE_IMAGE_CATEGORY] (state, imageCategory) {
      const cat = state.imageCategories.find(c => parseInt(c.id) === parseInt(imageCategory.id))
      const idx = state.imageCategories.indexOf(cat)

      state.imageCategories = [
        ...state.imageCategories.slice(0, idx),
        ...state.imageCategories.slice(idx + 1)
      ]
      state.imageCategory = {}
    }
  },

  getters: {
    allImageCategories: state => {
      return state.imageCategories
    },

    currentImageCategory: state => {
      return state.imageCategory
    }
  },

  actions: {
    async fetchImageCategories (context) {
      nprogress.start()
      const imageCategories = await imageAPI.getImageCategories()
      context.commit(STORE_IMAGE_CATEGORIES, imageCategories)
      nprogress.done()
      return imageCategories
    },

    async fetchImageCategory (context, { categoryId, queryVars }) {
      nprogress.start()
      const imageCategory = await imageAPI.getImageCategory(categoryId, queryVars)
      context.commit(STORE_IMAGE_CATEGORY, imageCategory)
      nprogress.done()
      return imageCategory
    },

    async createImageCategory (context, categoryParams) {
      nprogress.start()
      const imageCategory = await imageAPI.createImageCategory(categoryParams)
      context.commit(ADD_IMAGE_CATEGORY, imageCategory)
      nprogress.done()
      return imageCategory
    },

    async createImageSeries (context, imageSeriesParams) {
      nprogress.start()
      const imageSeries = await imageAPI.createImageSeries(imageSeriesParams)
      context.commit(ADD_IMAGE_SERIES, imageSeries)
      nprogress.done()
      return imageSeries
    },

    storeImage (context, image) {
      context.commit(STORE_IMAGE, image)
    },

    async deleteImage (context, { id, imageSeriesId }) {
      nprogress.start()
      context.commit(DELETE_IMAGE, { id, imageSeriesId })
      nprogress.done()
    },

    async deleteImageSeries (context, series) {
      nprogress.start()
      await imageAPI.deleteImageSeries(series.id)
      context.commit(DELETE_IMAGE_SERIES, series)
      nprogress.done()
    },

    async deleteImageCategory (context, category) {
      nprogress.start()
      await imageAPI.deleteImageCategory(category.id)
      context.commit(DELETE_IMAGE_CATEGORY, category)
      nprogress.done()
    },

    async duplicateImageCategory (context, category) {
      nprogress.start()
      let cat = await imageAPI.duplicateImageCategory(category.id)
      nprogress.done()
      return cat
    },

    sequenceImages (context, params) {
      context.commit(UPDATE_IMAGE_SERIES_SORT_ORDER, params)
    }
  }
}
