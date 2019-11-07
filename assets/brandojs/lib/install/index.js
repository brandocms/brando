import 'vue-multiselect/dist/vue-multiselect.min.css'
import 'flatpickr/dist/flatpickr.min.css'
import 'vex-js/dist/css/vex.css'
import 'izitoast/dist/css/iziToast.css'
import '@univers-agency/villain-editor/dist/villain-editor.css'

import moment from 'moment-timezone'
import Sortable from 'sortablejs'
import Vue from 'vue'
import Vuex from 'vuex'
import VueRouter from 'vue-router'
import BootstrapVue from 'bootstrap-vue'
import { ValidationProvider, ValidationObserver, extend, configure } from 'vee-validate'
import { required, email, max, confirmed, min } from 'vee-validate/dist/rules'
import Multiselect from 'vue-multiselect'
import vClickOutside from 'v-click-outside'

import VueIziToast from '../utils/toast'
import VuePhoenixSocket from '../utils/socket'
import VueUploadComponent from 'vue-upload-component'

import * as filters from '../filters'
import * as kurtzComponents from 'brandojs/lib/components'

import MOMENT_NB_LOCALE from './config/MOMENT_NB_LOCALE'

export function installKurtz () {
  moment.defineLocale('nb', MOMENT_NB_LOCALE)
  moment.locale('nb')
  moment.tz.setDefault('Europe/Oslo')

  // register Sortable as a global directive
  Vue.directive('sortable', {
    inserted: function (el, binding) {
      const s = new Sortable(el, binding.value || {})
      return s
    }
  })

  // register global utility filters.
  Object.keys(filters).forEach(key => {
    Vue.filter(key, filters[key])
  })

  // register all kurtz components
  for (const component in kurtzComponents) {
    Vue.component(component, kurtzComponents[component])
  }

  // Add the required rule
  extend('required', {
    ...required,
    message: 'Feltet er påkrevet'
  })

  // Add the email rule
  extend('email', {
    ...email,
    message: 'Må være en gyldig epostadresse'
  })

  // Add the max rule
  extend('max', {
    ...max,
    message: 'Kan maksimalt inneholde {length} tegn'
  })

  // Add the min rule
  extend('min', {
    ...min,
    message: 'Må minst inneholde {length} tegn'
  })

  // Add the max rule
  extend('confirmed', {
    ...confirmed,
    message: 'Bekreftelsesfeltet matcher ikke kildefeltet'
  })

  configure({
    useConstraintAttrs: false
  })

  Vue.component('ValidationObserver', ValidationObserver)
  Vue.component('ValidationProvider', ValidationProvider)

  Vue.use(Vuex)
  Vue.use(VueRouter)
  Vue.use(VueIziToast)
  Vue.use(VuePhoenixSocket)

  Vue.use(vClickOutside)
  Vue.use(BootstrapVue)
  Vue.component('FileUpload', VueUploadComponent)
  Vue.component('Multiselect', Multiselect)

  Vue.config.productionTip = false

  return Vue
}

export function installConfig (store, config) {
  store.commit('config/STORE_SETTING', config)
}
