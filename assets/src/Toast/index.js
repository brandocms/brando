import { animate, set } from '../motion'

// One stack of toasts in the bottom right corner, for two kinds of message:
//
// - notifications answer something the user did (`notification/2`): success
//   and info fade after a while, errors stay until closed;
// - mutations tell them what someone else just changed (`mutation/2`): quiet,
//   with the editor's initials, gone after a few seconds.
//
// Messages are set as text, never HTML: mutations carry entry titles.

const TIMEOUTS = { success: 5000, info: 5000, mutation: 4000 }
const MAX_VISIBLE = 5

export default class Toast {
  constructor(app) {
    this.app = app
    this.popupTimer = null
    this.popup = null

    this.stack = document.createElement('div')
    this.stack.className = 'toast-stack'
    // Polite: new toasts are read out without interrupting the user.
    this.stack.setAttribute('role', 'status')
    this.stack.setAttribute('aria-live', 'polite')
    document.body.appendChild(this.stack)
  }

  notification(level, message) {
    if (!['success', 'error', 'info'].includes(level)) return
    this.add({ kind: level, text: message })
  }

  mutation(_level, payload) {
    const { user, action, identifier } = payload
    const name = (user && user.name) || 'System'

    this.add({
      kind: 'mutation',
      initials: initials(name),
      build: $text => {
        const who = document.createElement('strong')
        who.textContent = name
        const what = document.createElement('span')
        what.className = 'toast-mono'
        what.textContent = `${identifier.type} #${identifier.entry_id}`
        $text.append(who, ` ${action} `, what, ` “${identifier.title}”`)
      }
    })
  }

  // The socket dropped: say so until it is back, then confirm it briefly.
  connection(connected, message) {
    this.remove(this.connectionToast)
    this.connectionToast = this.add({ kind: connected ? 'success' : 'error', text: message })
  }

  add({ kind, text, initials, build }) {
    const toast = document.createElement('div')
    toast.className = `toast toast--${kind}`

    const marker = document.createElement('span')
    if (initials) {
      marker.className = 'toast-initials'
      marker.textContent = initials
    } else {
      marker.className = 'toast-dot'
    }

    const $text = document.createElement('div')
    $text.className = 'toast-text'
    if (build) build($text)
    else $text.textContent = text

    toast.append(marker, $text)

    if (kind !== 'mutation') {
      const close = document.createElement('button')
      close.type = 'button'
      close.className = 'toast-close'
      close.setAttribute('aria-label', document.body.dataset.toastClose || 'Close')
      close.textContent = '×'
      close.addEventListener('click', () => this.remove(toast))
      toast.append(close)
    }

    this.stack.append(toast)
    animate(toast, { opacity: [0, 1], y: [8, 0] }, { duration: 0.18 })

    const timeout = TIMEOUTS[kind]
    if (timeout) {
      let timer = setTimeout(() => this.remove(toast), timeout)
      // Hovering holds a toast so it can be read.
      toast.addEventListener('mouseenter', () => clearTimeout(timer))
      toast.addEventListener('mouseleave', () => {
        timer = setTimeout(() => this.remove(toast), 1500)
      })
    }

    const toasts = this.stack.querySelectorAll('.toast:not(.leaving)')
    if (toasts.length > MAX_VISIBLE) this.remove(toasts[0])

    return toast
  }

  remove(toast) {
    if (!toast || !toast.isConnected || toast.classList.contains('leaving')) return
    toast.classList.add('leaving')
    animate(toast, { opacity: 0 }, { duration: 0.2 }).finished.then(() => toast.remove())
  }

  progressPopup(message) {
    // kill the close timer (if it exists)
    this.popupTimer && clearTimeout(this.popupTimer)

    this.popupTimer = setTimeout(() => {
      this.closePopup()
    }, 800)
    this.updatePopup(message)
  }

  updatePopup(message) {
    if (!this.popup) {
      this.msgNo = 1
      this.popup = document.createElement('div')
      this.popup.className = 'progress-popup'
      this.popup.innerHTML = `<div class="message">[${this.msgNo}] &rarr; ${message}</div>`
      set(this.popup, { opacity: 0 })
      document.body.appendChild(this.popup)
      this.popup.setAttribute('popover', '')
      if (typeof this.popup.showPopover === 'function') {
        this.popup.showPopover()
      }
      animate(this.popup, { opacity: 1 }, { duration: 0.15 })
    } else {
      this.msgNo++
      this.popup.querySelector('.message').innerHTML =
        `[${this.msgNo}] &rarr; ${message}`
      // A message during the fade-out brings the popup back. Starting a new
      // opacity animation stops the fade, and a stopped fade never finishes,
      // so the popup is not removed under the new message.
      animate(this.popup, { opacity: 1 }, { duration: 0.15 })
    }
  }

  closePopup() {
    const popup = this.popup
    if (popup) {
      animate(popup, { opacity: 0 }, { duration: 0.5 }).finished.then(() => {
        popup.remove()
        this.popup = null
      })
    }
  }
}

function initials(name) {
  return name
    .split(/\s+/)
    .filter(Boolean)
    .slice(0, 2)
    .map(part => part[0].toUpperCase())
    .join('')
}
