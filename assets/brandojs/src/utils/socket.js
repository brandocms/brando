/* TODO: extract to vue-phoenix-socket */

import { Socket } from 'phoenix'

const VuePhoenixSocket = {}

VuePhoenixSocket.install = function (Vue, options) {
  Vue.prototype.connectSocket = function () {
    const token = localStorage.getItem('token')
    let socket = new Socket('/admin/socket', { params: { guardian_token: token } })
    socket.onError(() => {
      Vue.prototype.$iziToast.error({ message: 'Ingen forbindelse til WS' })
    })
    socket.onClose(err => {
      console.error(err)
    })

    socket.connect()
    Vue.prototype.$socket = socket
  }
}

export default VuePhoenixSocket
