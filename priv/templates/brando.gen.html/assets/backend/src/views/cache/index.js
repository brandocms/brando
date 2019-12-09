import GET_<%= String.upcase(singular) %> from '../../../gql/<%= snake_domain %>/<%= String.upcase(singular) %>_QUERY.graphql'
import GET_<%= String.upcase(plural) %> from '../../../gql/<%= snake_domain %>/<%= String.upcase(plural) %>_QUERY.graphql'

export default {
  remove(provider, entry) {
    query = {
      query: GET_<%= String.upcase(plural) %>
    }

    try {
      data = store.readQuery(query)

      let foundEntry = data.<%= vue_plural %>.find(e => parseInt(e.id) === parseInt(entry.id))

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not found in cache
    }
  },

  add (provider, entry) {
    let query = {
      query: GET_ <%= String.upcase(plural) %>
    }

    const store = provider.defaultClient.store.cache

    try {
      let data = store.readQuery(query)

      data.<%= vue_plural %>.unshift(series)

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }
  }
}
