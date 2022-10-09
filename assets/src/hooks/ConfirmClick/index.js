import { alertConfirm } from '../../alerts'

export default (app) => ({
  mounted() {
    this.el.addEventListener('click', e => {
      e.preventDefault()
      e.stopPropagation()

      const event = this.el.getAttribute('phx-confirm-click')
      const message = this.el.getAttribute('phx-confirm-click-message')

      alertConfirm('OBS', message, confirmed => {
        if (confirmed !== false) {
          app.liveSocket.execJS(this.el, event)
        }
      })
    })
  }
})