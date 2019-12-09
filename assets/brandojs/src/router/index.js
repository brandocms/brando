import Vue from 'vue'
import VueRouter from 'vue-router'
import Dashboard from '../views/Dashboard'
import ProfileView from '../views/users/ProfileView'
import UserListView from '../views/users/UserListView'
import IdentityView from '../views/config/IdentityView'

import TemplatesView from '../views/pages/TemplatesView'
import PageListView from '../views/pages/PageListView'
import PageCreateView from '../views/pages/PageCreateView'
import PageEditView from '../views/pages/PageEditView'
import PageSectionCreateView from '../views/pages/PageSectionCreateView'
import PageSectionEditView from '../views/pages/PageSectionEditView'

import UserCreateView from '../views/users/UserCreateView'
import UserEditView from '../views/users/UserEditView'

import ImagesView from '../views/images/ImagesView'
import ImageCategoryDetailView from '../views/images/ImageCategoryDetailView'
import ImageCategoryEditView from '../views/images/ImageCategoryEditView'

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
    path: '/images',
    name: 'images',
    component: ImagesView
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
    path: '/files',
    name: 'files',
    component: IdentityView
  },
  {
    path: '/pages',
    name: 'pages',
    component: PageListView
  },
  {
    path: '/pages/templates',
    name: 'templates',
    component: TemplatesView
  },
  {
    path: '/pages/new',
    name: 'pages-new',
    component: PageCreateView
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
    console.log('no auth. ')
    next()
  } else {
    console.log('auth!')
    console.log(Vue.prototype)
    if (!token) {
      console.log('NO TOKEN')
      return router.replace({ name: 'login', query: { redirect: to.fullPath } })
    }
    next()
  }
})

export default router
