import <%= String.capitalize(singular) %>ListView from '@/views/<%= domain %>/<%= String.capitalize(singular) %>ListView'
import <%= String.capitalize(singular) %>CreateView from '@/views/<%= domain %>/<%= String.capitalize(singular) %>CreateView'
import <%= String.capitalize(singular) %>EditView from '@/views/<%= domain %>/<%= String.capitalize(singular) %>EditView'

export default [
  {
    path: '/<%= plural %>',
    component: <%= String.capitalize(singular) %>ListView,
    name: '<%= plural %>'
  },

  {
    path: '/<%= singular %>/ny',
    component: <%= String.capitalize(singular) %>CreateView,
    name: '<%= singular %>-new'
  },

  {
    path: '/<%= singular %>/endre/:<%= singular %>Id',
    component: <%= String.capitalize(singular) %>EditView,
    name: '<%= singular %>-edit',
    props: true
  },
]
