import { alertConfirm } from '../../alerts'

/**
 * Asks before running the element's `phx-confirm-click` JS/event.
 *
 * The dialog's text comes from the element: `phx-confirm-click-message`, and
 * optionally `-title`, `-confirm` and `-cancel` for the heading and buttons.
 * With `phx-confirm-click-describe` the hook first asks the LiveView (that
 * event, with the element's `phx-value-id`) and uses the title, message and
 * labels it replies with — for text that depends on the entry, like what a
 * delete takes with it.
 */
export default app => ({
  mounted() {
    this.el.addEventListener('click', e => {
      e.preventDefault()
      e.stopPropagation()

      let event = this.el.getAttribute('phx-confirm-click')

      // if the event is not a JS event, we need to convert it
      if (event.indexOf('[') === -1) {
        event = `[["push",{"event":"${event}"}]]`
      }

      // A menu the action sat in closes, rather than staying open over the dialog.
      this.el.closest('.dropdown-content')?.classList.add('hidden')
      const destructive = this.el.hasAttribute('phx-confirm-click-destructive')

      const confirm = ({ title, message, confirm, cancel }) =>
        alertConfirm(
          title,
          message,
          confirmed => {
            if (confirmed !== false) {
              app.liveSocket.execJS(this.el, event)
            }
          },
          { confirmText: confirm, cancelText: cancel, destructive }
        )

      const fromElement = {
        title: this.el.getAttribute('phx-confirm-click-title') || '',
        message: this.el.getAttribute('phx-confirm-click-message'),
        confirm: this.el.getAttribute('phx-confirm-click-confirm'),
        cancel: this.el.getAttribute('phx-confirm-click-cancel')
      }

      const describe = this.el.getAttribute('phx-confirm-click-describe')

      if (describe) {
        this.pushEvent(describe, { id: this.el.getAttribute('phx-value-id') }, reply =>
          confirm(reply && reply.message ? reply : fromElement)
        )
      } else {
        confirm(fromElement)
      }
    })
  }
})
