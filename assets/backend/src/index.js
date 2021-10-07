import 'vex-js/dist/css/vex.css'
import 'izitoast/dist/css/iziToast.css'
import 'flatpickr/dist/flatpickr.min.css'

import { abilitiesPlugin } from '@casl/vue'
import ability from './services/casl/defaultAbility'
import Sortable from 'sortablejs'
import VueShortkey from 'vue-shortkey'
import VueClickOutside from 'v-click-outside'
import { createProvider } from './vue-apollo'
import iziToast from 'izitoast'
import VuePhoenixSocket from './utils/socket'
import PortalVue from 'portal-vue'
import { ValidationProvider, ValidationObserver, extend, configure } from 'vee-validate'
import { required, email, max, confirmed, min } from 'vee-validate/dist/rules'
import { VTooltip } from 'v-tooltip'

import Admin from './Admin'
import Dropzone from './components/Dropzone'
import * as FormComponents from './components/form'
import * as ButtonComponents from './components/button'
import * as ContentComponents from './components/contents'
import * as ImageComponents from './components/images'
import * as NavigationComponents from './components/navigation'
import * as filters from './filters'

import './plugins/fontawesome'
import { utils } from './utils'
import { alerts } from './utils/alerts'
import defaultMenuSections from './menus'

import { gsap, CSSPlugin } from 'gsap'

gsap.registerPlugin(CSSPlugin)

iziToast.settings({
  title: '',
  position: 'topRight',
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

    Vue.directive('popover', VTooltip)

    // register global utility filters.
    Object.keys(filters).forEach(key => {
      Vue.filter(key, filters[key])
    })

    Vue.use(VueShortkey, { prevent: ['input', 'textarea'] })
    Vue.use(VueClickOutside)
    Vue.use(abilitiesPlugin, ability)
    Vue.use(PortalVue)

    // Vue.config.performance = true

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
    Vue.component('Dropzone', Dropzone)

    /**
     * Configure VeeValidate
     */

    // Add the required rule
    extend('required', {
      ...required
    })

    // Add the email rule
    extend('email', {
      ...email
    })

    // Add the max rule
    extend('max', {
      ...max
    })

    // Add the min rule
    extend('min', {
      ...min
    })

    // Add the max rule
    extend('confirmed', {
      ...confirmed
    })

    configure({
      useConstraintAttrs: false
    })

    Vue.component('ValidationObserver', ValidationObserver)
    Vue.component('ValidationProvider', ValidationProvider)

    Vue.prototype.$apolloProvider = createProvider()
    Vue.prototype.$utils = utils
    Vue.prototype.$alerts = alerts
    Vue.prototype.$toast = iziToast
    Vue.prototype.$app = app

    menuSections.forEach(section => {
      Object.keys(section).forEach(lang => {
        defaultMenuSections[lang][1].items = [
          ...defaultMenuSections[lang][1].items,
          ...(section[lang] ? section[lang] : [])
        ]
      })
    })

    Vue.prototype.$menu = { sections: defaultMenuSections }

    Vue.use(VuePhoenixSocket)
  }
}
