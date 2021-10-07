import { alertConfirm } from '../../alerts'

export default (app) => ({
  mounted() {
    this.el.addEventListener('click', e => {
      e.preventDefault()
      e.stopPropagation()

      const target = this.el.getAttribute('phx-target')
      const event = this.el.getAttribute('phx-confirm-click')
      const message = this.el.getAttribute('phx-confirm-click-message')
      const id = this.el.getAttribute('phx-value-id')
      const language = this.el.getAttribute('phx-value-language')

      alertConfirm('OBS', message, confirmed => {
        if (confirmed !== false) {
          if (target) {
            this.pushEventTo(`${target}`, event, { id, language })
          } else {
            this.pushEvent(event, { id, language })
          }
        }
      })
    })
  }
})