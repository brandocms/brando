import { nprogress } from 'brandojs'
import { identityAPI } from '../../api/identity'

const STORE_ORGANIZATION = 'STORE_ORGANIZATION'
const STORE_ORGANIZATIONS = 'STORE_ORGANIZATIONS'
const DELETE_ORGANIZATION = 'DELETE_ORGANIZATION'

export const identities = {
  namespaced: true,
  // initial state
  state: {
    identity: {},
    identities: []
  },

  // mutations
  mutations: {
    [DELETE_ORGANIZATION] (state, identity) {
      const pIdx = state.identities.indexOf(identity)

      state.identities = [
        ...state.identities.slice(0, pIdx),
        ...state.identities.slice(pIdx + 1)
      ]
    },

    [STORE_ORGANIZATION] (state, identity) {
      state.identity = identity
    },

    [STORE_ORGANIZATIONS] (state, identities) {
      state.identities = identities
    }
  },

  getters: {
    allIdentitys: state => {
      return state.identities
    }
  },

  actions: {
    async getIdentitys (context, variables) {
      nprogress.start()
      const identities = await identityAPI.getIdentitys(variables)
      context.commit(STORE_ORGANIZATIONS, identities)
      nprogress.done()
      return identities
    },

    async getIdentity (context, identityId) {
      nprogress.start()
      const identity = await identityAPI.getIdentity(identityId)
      context.commit(STORE_ORGANIZATION, identity)
      nprogress.done()
      return identity
    },

    async deleteIdentity (context, identity) {
      nprogress.start()
      await identityAPI.deleteIdentity(identity.id)
      context.commit(DELETE_ORGANIZATION, identity)
      nprogress.done()
      return identity
    }
  }
}
