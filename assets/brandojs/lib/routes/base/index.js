import { LoginView } from '../../views/auth'

import {
  IdentityView
} from '../../views/config'

import {
  ProfileView,
  UserCreateView,
  UserEditView,
  UserListView
} from '../../views/users'

import {
  ImageCategoryView,
  ImageCategoryListView,
  ImageCategoryDetailView,
  ImageCategoryConfigView,
  ImageSeriesConfigView
} from '../../views/images'

import {
  PageListView,
  PageCreateView,
  PageEditView
} from '../../views/pages'

import {
  PageFragmentCreateView,
  PageFragmentEditView
} from '../../views/pageFragments'

import {
  TemplateCreateView
} from '../../views/templates'

const authRoutes = [
  {
    path: '/login',
    component: LoginView,
    name: 'login',
    meta: { title: 'Login', noAuth: true }
  }
]

const configRoutes = [
  {
    path: '/konfigurasjon/identitet',
    component: IdentityView,
    name: 'config',
    meta: { title: 'Konfigurasjon/Identitet' }
  }
]

const templateRoutes = [
  {
    path: '/maler',
    component: TemplateCreateView,
    name: 'templates',
    meta: { title: 'Maler', fullScreen: true }
  }
]

const pageRoutes = [
  {
    path: '/sider',
    component: PageListView,
    name: 'pages',
    meta: { title: 'Sider' }
  },
  {
    path: '/side/ny',
    component: PageCreateView,
    name: 'page-create',
    meta: { title: 'Ny side', fullScreen: true }
  },
  {
    path: '/side/endre/:pageId',
    component: PageEditView,
    name: 'page-edit',
    meta: { title: 'Endre side', fullScreen: true },
    props: true
  }
]

const pageFragmentRoutes = [
  {
    path: '/sidefragment/ny/:pageId',
    component: PageFragmentCreateView,
    name: 'pagefragment-create',
    meta: { title: 'Nytt fragment', fullScreen: true },
    props: true
  },
  {
    path: '/sidefragment/endre/:pageId',
    component: PageFragmentEditView,
    name: 'pagefragment-edit',
    meta: { title: 'Endre fragment', fullScreen: true },
    props: true
  }
]

const userRoutes = [
  {
    path: '/profil',
    component: ProfileView,
    name: 'profile',
    meta: { title: 'Min profil' }
  },

  {
    path: '/brukere',
    component: UserListView,
    name: 'users',
    meta: { title: 'Brukere' }
  },

  {
    path: '/brukere/ny',
    component: UserCreateView,
    name: 'user-create',
    meta: { title: 'Opprett ny bruker' }
  },

  {
    path: '/brukere/endre/:userId',
    component: UserEditView,
    name: 'user-edit',
    meta: { title: 'Endre bruker' },
    props: true
  }
]

const imagesRoutes = [
  {
    path: '/bilder/serier/:seriesId/konfigurer',
    component: ImageSeriesConfigView,
    name: 'image-series-config',
    meta: { title: 'Konfigurer serie' },
    props: true
  },
  {
    path: '/bilder',
    component: ImageCategoryView,
    meta: { title: 'Bildeoversikt' },
    props: true,
    children: [
      { path: '', component: ImageCategoryListView, name: 'images', meta: { title: 'Bildeoversikt' }, props: true },
      { path: 'kategori/:categoryId', component: ImageCategoryDetailView, name: 'image-category-detail', meta: { title: 'Vis kategori' }, props: true },
      { path: 'kategori/:categoryId/konfigurer', component: ImageCategoryConfigView, name: 'image-category-config', meta: { title: 'Konfigurer kategori' }, props: true }
    ]
  }
]

export default [].concat(
  authRoutes,
  configRoutes,
  imagesRoutes,
  pageRoutes,
  pageFragmentRoutes,
  userRoutes,
  templateRoutes
)
