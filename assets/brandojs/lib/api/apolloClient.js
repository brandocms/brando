import ApolloClient from 'apollo-client'
import { ApolloLink } from 'apollo-link'
import { InMemoryCache } from 'apollo-cache-inmemory'
import { onError } from 'apollo-link-error'
import { createLink } from 'apollo-absinthe-upload-link'

const GQL_URI = '/admin/graphql'

class KurtzApolloClient {
  async initialize () {
    const httpLink = createLink({ uri: GQL_URI })
    const middlewareLink = new ApolloLink((operation, forward) => {
      this.token = localStorage.getItem('token')
      operation.setContext({
        headers: {
          authorization: this.token ? `Bearer ${this.token}` : null
        }
      })
      return forward(operation)
    })

    const errorLink = onError(({ networkError = {}, graphQLErrors }) => {
      if (networkError.statusCode === 406) {
        this.logout()
      }
    })

    const link = ApolloLink.from([middlewareLink, errorLink, httpLink])
    const cache = new InMemoryCache().restore(window.__APOLLO_STATE__)

    this.client = new ApolloClient({
      link: link,
      cache: cache
    })
  }

  logout () {
    localStorage.removeItem('token')
    window.location = '/admin/login?expired=true'
  }
}

const apolloClient = new KurtzApolloClient()

export default apolloClient
