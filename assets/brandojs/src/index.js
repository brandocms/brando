import '@univers-agency/villain-editor/dist/villain-editor.css'
import 'vex-js/dist/css/vex.css'
import 'izitoast/dist/css/iziToast.css'

import Sortable from 'sortablejs'
import { mapActions, mapGetters, mapState, mapMutations } from 'vuex'
import VueShortkey from 'vue-shortkey'
import VueClickOutside from 'v-click-outside'
import { createProvider } from './vue-apollo'
import iziToast from 'izitoast'
import { Socket } from 'phoenix'

import { ValidationProvider, ValidationObserver, extend, configure } from 'vee-validate'
import { required, email, max, confirmed, min } from 'vee-validate/dist/rules'

import VueUploadComponent from 'vue-upload-component'

import Admin from './Admin'
import * as FormComponents from './components/form'
import * as ButtonComponents from './components/button'
import * as ContentComponents from './components/contents'
import * as ImageComponents from './components/images'
import * as NavigationComponents from './components/navigation'
import * as filters from './filters'

import './plugins/fontawesome'
import store from './store'
import { utils } from './utils'
import { alerts } from './utils/alerts'
import defaultMenuSections from './menus'

iziToast.settings({
  position: 'topRight',
  title: '',
  animateInside: false,
  timeout: 5000,
  iconColor: '#ffffff',
  theme: 'brando'
})

export default {
  // The install method will be called with the Vue constructor as
  // the first argument, along with possible options
  install (Vue, { menuSections, app }) {
    Vue.config.productionTip = false

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

    Vue.use(VueShortkey)
    Vue.use(VueClickOutside)

    // register all nav components
    for (const component in NavigationComponents) {
      Vue.component(component, NavigationComponents[component])
    }

    // register all form components
    for (const component in FormComponents) {
      Vue.component(component, FormComponents[component])
    }

    // register all button components
    for (const component in ButtonComponents) {
      Vue.component(component, ButtonComponents[component])
    }

    // register all content components
    for (const component in ContentComponents) {
      Vue.component(component, ContentComponents[component])
    }

    // register all image components
    for (const component in ImageComponents) {
      Vue.component(component, ImageComponents[component])
    }

    Vue.component('Admin', Admin)
    Vue.component('FileUpload', VueUploadComponent)

    /**
     * Configure VeeValidate
     */

    // Add the required rule
    extend('required', {
      ...required,
      message: 'feltet er påkrevet'
    })

    // Add the email rule
    extend('email', {
      ...email,
      message: 'ugyldig epost'
    })

    // Add the max rule
    extend('max', {
      ...max,
      message: 'kan maksimalt inneholde {length} tegn'
    })

    // Add the min rule
    extend('min', {
      ...min,
      message: 'må minst inneholde {length} tegn'
    })

    // Add the max rule
    extend('confirmed', {
      ...confirmed,
      message: 'bekreftelsesfeltet matcher ikke kildefeltet'
    })

    configure({
      useConstraintAttrs: false
    })

    Vue.component('ValidationObserver', ValidationObserver)
    Vue.component('ValidationProvider', ValidationProvider)

    Vue.prototype.$apolloProvider = createProvider()
    Vue.prototype.$store = store
    Vue.prototype.$utils = utils
    Vue.prototype.$alerts = alerts
    Vue.prototype.$toast = iziToast
    Vue.prototype.$app = app

    const contentMenu = defaultMenuSections.find(s => s.name === 'Content')
    contentMenu.items = [
      ...contentMenu.items,
      ...menuSections
    ]

    Vue.prototype.$menu = { sections: defaultMenuSections }

    Vue.prototype.connectSocket = function () {
      const token = localStorage.getItem('token')
      let socket = new Socket('/admin/socket', { params: { guardian_token: token } })
      socket.onError(() => {
        Vue.prototype.$toast.error({ message: 'Ingen forbindelse til WS' })
      })
      socket.onClose(err => {
        console.error(err)
      })

      socket.connect()
      Vue.prototype.$socket = socket
    }

    // // Add or modify global methods or properties.
    // Vue.yourMethod = (value) => value
    // // Add a component or directive to your plugin, so it will be installed globally to your project.
    // Vue.component('component', Component)
    // // Add `Vue.mixin()` to inject options to all components.
    // Vue.mixin({
    //   // Add component lifecycle hooks or properties.
    //   created() {
    //     console.log('Hello from created hook!')
    //   }
    // })
    // // Add Vue instance methods by attaching them to Vue.prototype.
    // Vue.property.$myProperty = 'This is a Vue instance property.'
  }
}

export {
  mapActions, mapGetters, mapState, mapMutations
}
