import Vue from 'vue'
import VueApollo from 'vue-apollo'
import { createApolloClient } from 'vue-cli-plugin-apollo/graphql-client'
import { createLink } from 'apollo-absinthe-upload-link'
import { buildAxiosFetch } from '@lifeomic/axios-fetch'
import gql from 'graphql-tag'
import axios from 'axios'

// Install the vue plugin
Vue.use(VueApollo)

// Name of the localStorage item
const AUTH_TOKEN = 'token'
const httpEndpoint = process.env.VUE_APP_GRAPHQL_HTTP || '/admin/graphql'

const link = createLink({
  uri: httpEndpoint,
  fetch: buildAxiosFetch(axios, (config, input, init) => ({
    ...config,
    onUploadProgress: init.onUploadProgress
  }))
})

// Config
const defaultOptions = {
  // You can use `https` for secure connection (recommended in production)
  httpEndpoint,
  // LocalStorage token
  tokenName: AUTH_TOKEN,
  // Enable Automatic Query persisting with Apollo Engine
  persisting: false,
  // Use websockets for everything (no HTTP)
  // You need to pass a `wsEndpoint` for this to work
  websocketsOnly: false,
  // Is being rendered on the server?
  ssr: false,

  // Override default apollo link
  // note: don't override httpLink here, specify httpLink options in the
  // httpLinkOptions property of defaultOptions.
  link: link,
  defaultHttpLink: false,

  // Override the way the Authorization header is set
  getAuth: tokenName => {
    // get the authentication token from local storage if it exists
    const token = localStorage.getItem(AUTH_TOKEN)
    // return the headers to the context so httpLink can read them
    if (token) {
      return 'Bearer ' + token
    } else {
      return ''
    }
  },

  // Client local data (see apollo-link-state)
  typeDefs: gql`
    type Query {
      token: String!
    }

    type Query {
      fullscreen: Boolean!
    }
  `,
  resolvers: {
    Mutation: {
      tokenSet: (root, { value }, { cache }) => {
        const data = {
          token: value
        }
        cache.writeData({ data })
      },

      fullscreenSet: (root, { value }, { cache }) => {
        const data = {
          fullscreen: value
        }
        cache.writeData({ data })
      }
    }
  },

  onCacheInit: cache => {
    cache.originalReadQuery = cache.readQuery
    cache.readQuery = (...args) => {
      try {
        return cache.originalReadQuery(...args)
      } catch (err) {
        return undefined
      }
    }
    const data = {
      token: null,
      fullscreen: false
    }
    cache.writeData({ data })
  }
}

let PREVIOUS_ERROR

// Call this in the Vue app file
export function createProvider (options = {}) {
  // Create apollo client
  const { apolloClient, wsClient } = createApolloClient({
    ...defaultOptions,
    ...options
  })
  apolloClient.wsClient = wsClient

  // Create vue apollo provider
  const apolloProvider = new VueApollo({
    defaultClient: apolloClient,
    defaultOptions: {
      $query: {
        fetchPolicy: 'cache-and-network'
      }
    },

    async errorHandler (err) {
      const { networkError, graphQLErrors } = err

      if (PREVIOUS_ERROR === graphQLErrors) {
        return
      }

      PREVIOUS_ERROR = graphQLErrors

      if (networkError) {
        switch (networkError.statusCode) {
          case 422:
            Vue.prototype.$alerts.alertError('Valideringsfeil', err.error)
            break
          case 406:
            await onLogout(apolloClient)
            window.location = '/admin/login'
            break
          default:
            if (graphQLErrors && graphQLErrors.length) {
              Vue.prototype.$alerts.alertError('Feil', graphQLErrors.map(e => e.message).join('<br>'))
            } else if (networkError.error) {
              Vue.prototype.$alerts.alertError('Feil', networkError.error)
            } else {
              Vue.prototype.$alerts.alertError('Ukjent feil', err.message)
              console.error(err)
            }
        }
      } else {
        Vue.prototype.$alerts.alertError('Feil', graphQLErrors.map(e => e.message).join('<br>'))
      }
      // eslint-disable-next-line no-console
      console.error('%cB/GQLError', 'background: red; color: white; padding: 2px 4px; border-radius: 3px; font-weight: bold;', graphQLErrors)
    }
  })

  return apolloProvider
}

// Manually call this when user log in
export async function onLogin (apolloClient, token) {
  try {
    setTimeout(() => { apolloClient.resetStore() }, 0)
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('%cError on cache reset (login)', 'color: orange;', e.message)
  }
}

// Manually call this when user log out
export async function onLogout (apolloClient) {
  try {
    setTimeout(() => {
      apolloClient.resetStore()
      localStorage.removeItem('token')
    }, 0)
  } catch (e) {
    // eslint-disable-next-line no-console
    console.error('%cError on cache reset (logout)', 'color: orange;', e.message)
  }
}
