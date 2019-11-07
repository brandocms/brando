import nprogress from 'nprogress'
import {
  ADD_PAGE,
  STORE_PAGE,
  STORE_PAGES,
  DELETE_PAGE,
  ADD_PAGE_FRAGMENT,
  DELETE_PAGE_FRAGMENT
} from './mutation-types'

import { pageAPI } from '../api/page'

export const pages = {
  namespaced: true,
  // initial state
  state: {
    page: {},
    pages: []
  },

  // mutations
  mutations: {
    [DELETE_PAGE] (state, pageId) {
      const p = state.pages.find(p => parseInt(p.id) === parseInt(pageId))
      const pIdx = state.pages.indexOf(p)

      state.pages = [
        ...state.pages.slice(0, pIdx),
        ...state.pages.slice(pIdx + 1)
      ]
    },

    [DELETE_PAGE_FRAGMENT] (state, { pageFragmentId, pageId }) {
      let p = state.pages.find(p => parseInt(p.id) === parseInt(pageId))
      let pIdx = state.pages.indexOf(p)

      let f = p.fragments.find(f => parseInt(f.id) === parseInt(pageFragmentId))
      let fIdx = p.fragments.indexOf(f)

      state.pages = [
        ...state.pages.slice(0, pIdx),
        { ...p,
          fragments: [
            ...p.fragments.slice(0, fIdx),
            ...p.fragments.slice(fIdx + 1)
          ] },
        ...state.pages.slice(pIdx + 1)
      ]
    },

    [ADD_PAGE_FRAGMENT] (state, { pageFragment, pageId }) {
      let p = state.pages.find(p => parseInt(p.id) === parseInt(pageId))
      let pIdx = state.pages.indexOf(p)

      state.pages = [
        ...state.pages.slice(0, pIdx),
        { ...p,
          fragments: [
            pageFragment,
            ...p.fragments
          ]
        },
        ...state.pages.slice(pIdx + 1)
      ]
    },

    [ADD_PAGE] (state, page) {
      state.pages = [
        page,
        ...state.pages
      ]
    },

    [STORE_PAGE] (state, page) {
      state.page = page
    },

    [STORE_PAGES] (state, pages) {
      state.pages = pages
    }
  },

  getters: {
    allPages: state => {
      return state.pages
    }
  },

  actions: {
    async getPages (context, variables) {
      nprogress.start()
      const pages = await pageAPI.getPages(variables)
      context.commit(STORE_PAGES, pages)
      nprogress.done()
      return pages
    },

    async getPage (context, pageId) {
      nprogress.start()
      const page = await pageAPI.getPage(pageId)
      context.commit(STORE_PAGE, page)
      nprogress.done()
      return page
    }
  }
}
