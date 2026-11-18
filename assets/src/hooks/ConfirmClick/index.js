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
 *
 * All of it is text. A reply may carry `html` instead of `message`: markup the
 * server built and escaped (BrandoAdmin.LiveView.Listing.DeleteDescription
 * links the places a media file is used).
 *
 * A reply may also carry a `choice` (see `alertConfirm`): the values chosen
 * are added to the event's push, as a page's delete says where its
 * fragments go.
 */
// The chosen values join each push of the JS command
function withValues(event, values) {
  if (!values || typeof values !== 'object') return event

  const commands = JSON.parse(event).map(([kind, args]) =>
    kind === 'push' ? [kind, { ...args, value: { ...(args.value || {}), ...values } }] : [kind, args]
  )

  return JSON.stringify(commands)
}

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

      const confirm = ({ title, message, html, confirm, cancel, choice }) =>
        alertConfirm(
          title,
          typeof html === 'string' ? { html } : message,
          confirmed => {
            if (confirmed !== false) {
              app.liveSocket.execJS(this.el, withValues(event, confirmed))
            }
          },
          { confirmText: confirm, cancelText: cancel, destructive, choice }
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
          confirm(reply && (reply.message || reply.html) ? reply : fromElement)
        )
      } else {
        confirm(fromElement)
      }
    })
  }
})
