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
    path: '/<%= singular %>/ny',
    component: <%= Recase.to_pascal(vue_singular) %>CreateView,
    name: '<%= singular %>-new'
  },

  {
    path: '/<%= singular %>/endre/:<%= singular %>Id',
    component: <%= Recase.to_pascal(vue_singular) %>EditView,
    name: '<%= singular %>-edit',
    props: true
  }
]
