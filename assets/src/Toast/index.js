import iziToast from 'izitoast'
import { gsap } from '@brandocms/jupiter'

export default class Toast {
  constructor(app) {
    this.app = app
    this.izitoast = iziToast
    this.izitoast.settings({
      title: '',
      position: 'topRight',
      animateInside: false,
      timeout: 5000,
      iconColor: '#ffffff',
      theme: 'brando',
    })

    this.popupTimer = null
    this.popup = null
  }

  notification(level, message) {
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
      document.body.appendChild(this.popup)
      gsap.set(this.popup, { opacity: 0 })
      this.popup.setAttribute('popover', '')
      if (typeof this.popup.showPopover === 'function') {
        this.popup.showPopover()
      }
      gsap.to(this.popup, { opacity: 1, duration: 0.15 })
    } else {
      this.msgNo++
      this.popup.querySelector('.message').innerHTML =
        `[${this.msgNo}] &rarr; ${message}`
    }
  }

  closePopup() {
    if (this.popup) {
      gsap.to(this.popup, {
        opacity: 0,
        duration: 0.5,
        onComplete: () => {
          this.popup.remove()
          this.popup = null
        },
      })
    }
  }

  show(opts) {
    this.izitoast.show(opts)
  }

  mutation(level, payload) {
    this.izitoast.show({
      title: payload.user.name || '',
      message: `${payload.action} [${payload.identifier.type}#<strong>${payload.identifier.entry_id}</strong>] &raquo; "${payload.identifier.title}"`,
      theme: 'mutations',
      displayMode: 2,
      position: 'bottomRight',
      close: false,
      progressBar: false,
    })
  }
}
