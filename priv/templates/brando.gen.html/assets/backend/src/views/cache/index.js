import GET_<%= String.upcase(singular) %> from '../../../gql/<%= snake_domain %>/<%= String.upcase(singular) %>_QUERY.graphql'
import GET_<%= String.upcase(plural) %> from '../../../gql/<%= snake_domain %>/<%= String.upcase(plural) %>_QUERY.graphql'

export default {
  remove(provider, entry) {
    const store = provider.defaultClient.store.cache

    let query = {
      query: GET_<%= String.upcase(plural) %>
    }

    try {
      let data = store.readQuery(query)
      let foundEntry = data.<%= vue_plural %>.find(e => parseInt(e.id) === parseInt(entry.id))
      let foundIdx = data.<%= vue_plural %>.indexOf(foundEntry)
      if (foundIdx !== -1) {
        data.<%= vue_plural %> = [
          ...data.<%= vue_plural %>.slice(0, foundIdx),
          ...data.<%= vue_plural %>.slice(foundIdx + 1)
        ]

        store.writeQuery({
          ...query,
          data
        })
      }

    } catch (err) {
      // not found in cache
    }
  },

  add (provider, entry) {
    let query = {
      query: GET_<%= String.upcase(plural) %>
    }

    const store = provider.defaultClient.store.cache

    try {
      let data = store.readQuery(query)

      data.<%= vue_plural %>.unshift(entry)

      store.writeQuery({
        ...query,
        data
      })
    } catch (err) {
      // not in store
    }
  }
}
