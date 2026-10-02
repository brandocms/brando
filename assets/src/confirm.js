import { alertConfirm } from './alerts'

/**
 * `data-confirm="Really?"` on anything clickable: ask before the click does
 * its work. A phx-click, a link and a submit button all wait for the answer.
 * `data-confirm-destructive` gives the red dialog, with Cancel focused.
 * Optional `data-confirm-title` makes the dialog a question with the message
 * under it, and `data-confirm-ok` / `data-confirm-cancel` name its buttons
 * (say "Recreate sizes" rather than "OK"). Without a title the message is the
 * dialog's heading.
 *
 * Nothing else in the admin reads the attribute (phoenix_html's script, which
 * does on ordinary Phoenix pages, isn't loaded here), so without this a
 * `data-confirm` button acts at once.
 *
 * It listens on window in the capture phase, ahead of LiveView's own click
 * binding, which is what lets it hold the click back. An answered click is
 * sent again and let through once.
 */
export default function installConfirm() {
  const confirmed = new WeakSet()

  window.addEventListener(
    'click',
    e => {
      const el = e.target instanceof Element ? e.target.closest('[data-confirm]') : null
      if (!el) return

      const message = el.getAttribute('data-confirm')
      if (!message || message === 'false') return

      if (confirmed.has(el)) {
        confirmed.delete(el)
        return
      }

      e.preventDefault()
      e.stopImmediatePropagation()

      // The attributes are plain text; the dialog takes HTML.
      const escape = value => {
        const text = document.createElement('span')
        text.textContent = value || ''
        return text.innerHTML
      }

      alertConfirm(
        escape(el.getAttribute('data-confirm-title')),
        escape(message),
        ok => {
          if (!ok) return
          // A patch may have replaced the element while the dialog was open.
          const target = el.isConnected ? el : el.id && document.getElementById(el.id)
          if (!target) return
          confirmed.add(target)
          target.click()
        },
        {
          destructive: el.hasAttribute('data-confirm-destructive'),
          confirmText: el.getAttribute('data-confirm-ok'),
          cancelText: el.getAttribute('data-confirm-cancel')
        }
      )
    },
    true
  )
}
