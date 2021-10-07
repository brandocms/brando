import 'izitoast/dist/css/iziToast.css'
import '../../css/components/Toast.css'
import iziToast from 'izitoast'

export default class Toast {
  constructor (app) {
    this.app = app
    this.izitoast = iziToast
    this.izitoast.settings({
      title: '',
      position: 'topRight',
      animateInside: false,
      timeout: 5000,
      iconColor: '#ffffff',
      theme: 'brando'
    })
  }

  notification (level, message) {
    switch (level) {
      case 'success':
        this.izitoast.success({ message })
        break

      case 'error':
        this.izitoast.error({ message })
        break

      case 'info':
        this.izitoast.info({ message })
        break

      default:
        break
    }
  }

  show (opts) {
    this.izitoast.show(opts)
  }

  mutation (level, payload) {
    this.izitoast.show({
      title: payload.user.name || '',
      message: `${payload.action} [${payload.identifier.type}#<strong>${payload.identifier.id}</strong>] &raquo; "${payload.identifier.title}"`,
      theme: 'mutations',
      displayMode: 2,
      position: 'bottomRight',
      close: false,
      progressBar: false
    })
  }
}