import Vue from 'vue'
import VueRouter from 'vue-router'
import ProfileView from '../views/users/ProfileView'
import UserListView from '../views/users/UserListView'
import IdentityView from '../views/config/IdentityView'
import SEOView from '../views/config/SEOView'
import CacheView from '../views/config/CacheView'
import GlobalsView from '../views/config/GlobalsView'
import PublisherView from '../views/config/PublisherView'

import FilesView from '../views/files/FilesView'

import ModuleView from '../views/pages/ModuleView'
import ModuleListView from '../views/pages/ModuleListView'

import PageListView from '../views/pages/PageListView'
import PageCreateView from '../views/pages/PageCreateView'
import PageEditView from '../views/pages/PageEditView'
import PageSectionCreateView from '../views/pages/PageSectionCreateView'
import PageSectionEditView from '../views/pages/PageSectionEditView'

import UserCreateView from '../views/users/UserCreateView'
import UserCreatePasswordView from '../views/users/UserCreatePasswordView'
import UserEditView from '../views/users/UserEditView'

import ImagesView from '../views/images/ImagesView'
import ImageCategoryDetailView from '../views/images/ImageCategoryDetailView'
import ImageCategoryEditView from '../views/images/ImageCategoryEditView'
import ImageSeriesEditView from '../views/images/ImageSeriesEditView'

import MenuListView from '../views/navigation/MenuListView'
import MenuCreateView from '../views/navigation/MenuCreateView'
import MenuEditView from '../views/navigation/MenuEditView'
import MenuItemCreateView from '../views/navigation/MenuItemCreateView'
import MenuItemEditView from '../views/navigation/MenuItemEditView'

import LoginView from '../views/auth/LoginView'
import LogoutView from '../views/auth/LogoutView'

Vue.use(VueRouter)

const routes = [
  {
    path: '/login',
    component: LoginView,
    name: 'login',
    meta: { title: 'Login', noAuth: true }
  },
  {
    path: '/logout',
    component: LogoutView,
    name: 'logout',
    meta: { title: 'Logout', noAuth: true }
  },
  {
    path: '/profile',
    name: 'profile',
    component: ProfileView
  },
  {
    path: '/config/identity',
    name: 'config-identity',
    component: IdentityView
  },
  {
    path: '/config/seo',
    name: 'config-seo',
    component: SEOView
  },
  {
    path: '/config/publisher',
    name: 'config-publisher',
    component: PublisherView
  },
  {
    path: '/config/globals',
    name: 'config-globals',
    component: GlobalsView
  },
  {
    path: '/config/cache',
    name: 'config-cache',
    component: CacheView
  },
  {
    path: '/files',
    name: 'files',
    component: FilesView
  },
  {
    path: '/images',
    name: 'images',
    component: ImagesView
  },
  {
    path: '/images/series/edit/:imageSeriesId',
    name: 'image-series-edit',
    component: ImageSeriesEditView,
    props: route => {
      const imageSeriesId = Number.parseInt(route.params.imageSeriesId, 10)
      if (Number.isNaN(imageSeriesId)) {
        return 0
      }
      return { imageSeriesId }
    }
  },
  {
    path: '/images/categories/edit/:imageCategoryId',
    name: 'image-category-edit',
    component: ImageCategoryEditView,
    props: (route) => {
      const imageCategoryId = Number.parseInt(route.params.imageCategoryId, 10)
      if (Number.isNaN(imageCategoryId)) {
        return 0
      }
      return { imageCategoryId }
    }
  },
  {
    path: '/images/categories/:imageCategoryId',
    name: 'image-category-detail',
    component: ImageCategoryDetailView,
    props: (route) => {
      const imageCategoryId = Number.parseInt(route.params.imageCategoryId, 10)
      if (Number.isNaN(imageCategoryId)) {
        return 0
      }
      return { imageCategoryId }
    }
  },

  {
    path: '/navigation',
    name: 'navigation',
    component: MenuListView
  },

  {
    path: '/navigation/menu/new',
    name: 'navigation-new',
    component: MenuCreateView
  },

  {
    path: '/navigation/menu/edit/:menuId',
    name: 'navigation-edit',
    component: MenuEditView,
    props: (route) => {
      const menuId = Number.parseInt(route.params.menuId, 10)
      if (Number.isNaN(menuId)) {
        return 0
      }
      return { menuId }
    }
  },

  {
    path: '/navigation/menuitem/:menuId/new',
    name: 'navigation-items-new',
    component: MenuItemCreateView,
    props: (route) => {
      const menuId = Number.parseInt(route.params.menuId, 10)
      if (Number.isNaN(menuId)) {
        return 0
      }
      return { menuId }
    }
  },

  {
    path: '/navigation/menuitem/:menuItemId/edit',
    name: 'navigation-items-edit',
    component: MenuItemEditView,
    props: (route) => {
      const menuItemId = Number.parseInt(route.params.menuItemId, 10)
      if (Number.isNaN(menuItemId)) {
        return 0
      }
      return { menuItemId }
    }
  },

  {
    path: '/pages',
    name: 'pages',
    component: PageListView
  },

  {
    path: '/pages/modules',
    name: 'modules',
    component: ModuleListView
  },

  {
    path: '/pages/modules/:moduleId',
    name: 'modules-edit',
    component: ModuleView,
    props: (route) => {
      const moduleId = Number.parseInt(route.params.moduleId, 10)
      if (Number.isNaN(moduleId)) {
        return 0
      }
      return { moduleId }
    }
  },

  {
    path: '/pages/:pageId?/new',
    name: 'pages-new',
    component: PageCreateView,
    props: (route) => {
      const pageId = Number.parseInt(route.params.pageId, 10)
      if (Number.isNaN(pageId)) {
        return 0
      }
      return { pageId }
    }
  },

  {
    path: '/pages/edit/:pageId',
    name: 'pages-edit',
    component: PageEditView,
    props: (route) => {
      const pageId = Number.parseInt(route.params.pageId, 10)
      if (Number.isNaN(pageId)) {
        return 0
      }
      return { pageId }
    }
  },

  {
    path: '/pages/:pageId/sections/new',
    name: 'sections-new',
    component: PageSectionCreateView,
    props: (route) => {
      const pageId = Number.parseInt(route.params.pageId, 10)
      if (Number.isNaN(pageId)) {
        return 0
      }
      return { pageId }
    }
  },

  {
    path: '/pages/sections/edit/:sectionId',
    name: 'sections-edit',
    component: PageSectionEditView,
    props: (route) => {
      const sectionId = Number.parseInt(route.params.sectionId, 10)
      if (Number.isNaN(sectionId)) {
        return 0
      }
      return { sectionId }
    }
  },

  {
    path: '/users',
    name: 'users',
    component: UserListView
  },

  {
    path: '/users/new',
    name: 'users-new',
    component: UserCreateView
  },

  {
    path: '/users/new-password',
    name: 'users-new-password',
    component: UserCreatePasswordView
  },

  {
    path: '/users/edit/:userId',
    name: 'users-edit',
    component: UserEditView,
    props: true
  }
]

const router = new VueRouter({
  base: 'admin',
  mode: 'history',
  linkActiveClass: 'active',
  routes
})

router.beforeEach((to, from, next) => {
  const token = localStorage.getItem('token')
  // check if the user needs to be authenticated.
  // If yes, redirect to the login page if the token is null
  if (to.matched.some(m => m.meta.noAuth)) {
    next()
  } else {
    if (!token) {
      return router.replace({ name: 'login', query: { redirect: to.fullPath } })
    }
    next()
  }
})

export default router
