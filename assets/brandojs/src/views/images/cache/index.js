import GET_IMAGE_CATEGORY from '../../../gql/images/IMAGE_CATEGORY_QUERY.graphql'
import GET_IMAGE_CATEGORIES from '../../../gql/images/CATEGORIES_QUERY.graphql'

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
    let idx = data.imageCategory.image_series.findIndex(s => parseInt(s.id) === parseInt(series.id))

    if (idx !== -1) {
      data.imageCategory.image_series.splice(idx, 1)

      store.writeQuery({
        ...query,
        data
      })
    }

    query = {
      query: GET_IMAGE_CATEGORIES
    }

    data = store.readQuery(query)

    console.log(data)
    let category = data.imageCategories.find(c => parseInt(c.id) === parseInt(series.image_category_id))
    category.image_series_count = parseInt(category.image_series_count) - 1

    store.writeQuery({
      ...query,
      data
    })
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
      let data = store.readQuery(query)

      data.imageCategory.image_series.unshift(series)

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
      let data = store.readQuery(query)

      let category = data.imageCategories.find(c => parseInt(c.id) === parseInt(series.image_category_id))
      category.image_series_count = parseInt(category.image_series_count) + 1

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }
  }
}
