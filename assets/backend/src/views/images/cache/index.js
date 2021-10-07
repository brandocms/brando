import GET_IMAGE_CATEGORY from '../../../gql/images/IMAGE_CATEGORY_QUERY.graphql'
import GET_IMAGE_CATEGORIES from '../../../gql/images/IMAGE_CATEGORIES_QUERY.graphql'

export default {
  removeSeries (provider, series) {
    let query = {
      query: GET_IMAGE_CATEGORY,
      variables: {
        categoryId: parseInt(series.image_category_id)
      }
    }

    const store = provider.defaultClient.store.cache
    let data = store.readQuery(query)
    const idx = data.imageCategory.imageSeries.findIndex(s => parseInt(s.id) === parseInt(series.id))

    if (idx !== -1) {
      data.imageCategory.imageSeries.splice(idx, 1)

      store.writeQuery({
        ...query,
        data
      })
    }

    try {
      query = {
        query: GET_IMAGE_CATEGORIES
      }

      data = store.readQuery(query)

      const category = data.imageCategories.find(c => parseInt(c.id) === parseInt(series.image_category_id))
      category.imageSeriesCount = parseInt(category.imageSeriesCount) - 1

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }
  },

  addSeries (provider, series, categoryId) {
    let query = {
      query: GET_IMAGE_CATEGORY,
      variables: {
        categoryId: parseInt(categoryId)
      }
    }

    const store = provider.defaultClient.store.cache

    try {
      const data = store.readQuery(query)

      data.imageCategory.imageSeries.unshift(series)

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }

    query = {
      query: GET_IMAGE_CATEGORIES
    }

    try {
      const data = store.readQuery(query)

      const category = data.imageCategories.find(c => parseInt(c.id) === parseInt(series.image_category_id))
      category.imageSeriesCount = parseInt(category.imageSeriesCount) + 1

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }
  }
}
