import { nprogress } from 'brandojs'
import { linkAPI } from '../../api/link'

const STORE_LINK = 'STORE_LINK'
const STORE_LINKS = 'STORE_LINKS'
const DELETE_LINK = 'DELETE_LINK'

export const links = {
  namespaced: true,
  // initial state
  state: {
    link: {},
    links: []
  },

  // mutations
  mutations: {
    [DELETE_LINK] (state, link) {
      const pIdx = state.links.indexOf(link)

      state.links = [
        ...state.links.slice(0, pIdx),
        ...state.links.slice(pIdx + 1)
      ]
    },

    [STORE_LINK] (state, link) {
      state.link = link
    },

    [STORE_LINKS] (state, links) {
      state.links = links
    }
  },

  getters: {
    allLinks: state => {
      return state.links
    }
  },

  actions: {
    async getLinks (context, variables) {
      nprogress.start()
      const links = await linkAPI.getLinks(variables)
      context.commit(STORE_LINKS, links)
      nprogress.done()
      return links
    },

    async getLink (context, linkId) {
      nprogress.start()
      const link = await linkAPI.getLink(linkId)
      context.commit(STORE_LINK, link)
      nprogress.done()
      return link
    },

    async deleteLink (context, link) {
      nprogress.start()
      await linkAPI.deleteLink(link.id)
      context.commit(DELETE_LINK, link)
      nprogress.done()
      return link
    }
  }
}
