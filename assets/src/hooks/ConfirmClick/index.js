import { alertConfirm } from '../../alerts'

export default app => ({
  mounted() {
    this.el.addEventListener('click', e => {
      e.preventDefault()
      e.stopPropagation()

      let event = this.el.getAttribute('phx-confirm-click')
      const message = this.el.getAttribute('phx-confirm-click-message')

      // if the event is not a JS event, we need to convert it
      if (event.indexOf('[') === -1) {
        event = `[["push",{"event":"${event}"}]]`
      }

      alertConfirm('OBS', message, confirmed => {
        if (confirmed !== false) {
          app.liveSocket.execJS(this.el, event)
        }
      })
    })
  },
})
