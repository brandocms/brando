import <%= Recase.to_pascal(vue_singular) %>ListView from '@/views/<%= snake_domain %>/<%= Recase.to_pascal(vue_singular) %>ListView'
import <%= Recase.to_pascal(vue_singular) %>CreateView from '@/views/<%= snake_domain %>/<%= Recase.to_pascal(vue_singular) %>CreateView'
import <%= Recase.to_pascal(vue_singular) %>EditView from '@/views/<%= snake_domain %>/<%= Recase.to_pascal(vue_singular) %>EditView'

export default [
  {
    path: '/<%= plural %>',
    component: <%= Recase.to_pascal(vue_singular) %>ListView,
    name: '<%= plural %>'
  },

  {
    path: '/<%= plural %>/new',
    component: <%= Recase.to_pascal(vue_singular) %>CreateView,
    name: '<%= plural %>-new'
  },

  {
    path: '/<%= plural %>/edit/:<%= singular %>Id',
    component: <%= Recase.to_pascal(vue_singular) %>EditView,
    name: '<%= plural %>-edit',
    props: (route) => {
      const <%= singular %>Id = Number.parseInt(route.params.<%= singular %>Id, 10)
      if (Number.isNaN(<%= singular %>Id)) {
        return 0
      }
      return { <%= singular %>Id }
    }
  }
]
