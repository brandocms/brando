import { Dom, Events, gsap } from '@brandocms/jupiter'
import tippy from 'tippy.js'

export default (app) => ({
  mounted() {
    console.log('==> Form mounted')
    this.skipKeydown = this.el.hasAttribute('data-skip-keydown')
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')
    this.submitListenerEvent = this.submitListener.bind(this)

    if (!this.skipKeydown) {
      window.addEventListener('keydown', this.submitListenerEvent, false)
    }

    this.handleEvent(`b:validate`, (opts) => {
      if (opts.target) {
        const sel = `[name="${opts.target}"]`
        const target = this.$form.querySelector(sel)
        if (target) {
          if (opts.hasOwnProperty('value')) {
            target.value = opts.value
          }
          target.dispatchEvent(new Event('input', { bubbles: true }))
          return
        }
      }
      this.$input.dispatchEvent(new Event('input', { bubbles: true }))
    })

    this.handleEvent('b:set_active_field', (opts) => {
      const fieldPresence = document.querySelector(
        `[data-field-presence="${opts.field}"] .field-presence`
      )

      if (fieldPresence) {
        // see if we find any other presence indicators from this user
        const otherFieldPresence = document.querySelector(
          `.field-presence-user[data-user-id="${opts.user_id}"]`
        )

        if (otherFieldPresence) {
          // if it's presence indicator for the same field, just return
          const otherFieldPresenceFor =
            otherFieldPresence.getAttribute('data-presence-for')
          if (otherFieldPresenceFor === opts.field) {
            return
          }
          otherFieldPresence.remove()
        }
        // create a new presence indicator
        const presence = document.createElement('div')
        // create a data-user-id attribute on presence
        presence.setAttribute('data-user-id', opts.user_id)
        presence.setAttribute('data-presence-for', opts.field)
        presence.classList.add('field-presence-user')
        // grab the user's avatar from the page presences
        const userAvatar = document.querySelector(
          `.page-presences [data-presence-user-id="${opts.user_id}"] .avatar`
        )

        if (userAvatar) {
          const clonedAvatar = userAvatar.cloneNode(true)
          presence.appendChild(clonedAvatar)
          // append the presence indicator to the field presence
          fieldPresence.appendChild(presence)
          tippy(clonedAvatar, {
            allowHTML: true,
            content: clonedAvatar.dataset.popover,
          })
        }
      }
    })
  },

  destroyed() {
    if (!this.skipKeydown) {
      window.removeEventListener('keydown', this.submitListenerEvent, false)
    }
  },

  submitListener(ev) {
    if (ev.metaKey && ev.shiftKey && ev.key.toLowerCase() === 's') {
      ev.preventDefault()

      this.$form.dispatchEvent(
        new Event('submit', { bubbles: true, cancelable: true })
      )
      return
    }

    if (ev.metaKey && ev.key === 's') {
      ev.preventDefault()
      this.pushEventTo(this.el, 'save_redirect_target', {
        save_redirect_target: 'self',
      })
      setTimeout(() => {
        this.$form.dispatchEvent(
          new Event('submit', { bubbles: true, cancelable: true })
        )
      }, 150)
    }
  },
})
