import { Dom, Events, gsap } from '@brandocms/jupiter'
import tippy from 'tippy.js'
import {
  blockLocks,
  applyBlockLock,
  setBlockLock,
  clearBlockLock,
  clearUserBlockLocks,
  getPresenceColor,
} from '../../Presence/blockLocks'

export default (app) => ({
  mounted() {
    this.skipKeydown = this.el.hasAttribute('data-skip-keydown')
    this.$form = this.el.querySelector('form.main-form')
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

    this.handleEvent('b:show_drawer', ({ drawer_id }) => {
      const drawer = document.getElementById(drawer_id)
      if (drawer) {
        drawer.classList.remove('hidden', 'x-100')
        drawer.classList.add('x-0')
      }
    })

    // Lock state lives in the shared blockLocks map, DOM classes are just
    // its projection — LiveView patches reset a block's class attribute to
    // server truth, wiping imperatively added lock decorations (locks used
    // to flicker off whenever a locked block re-rendered, e.g. when its
    // owner's shipped edit applied). The Block hook re-asserts its own lock
    // from the map after every patch.
    this.handleEvent('b:set_active_block', ({ uid, user_id }) => {
      setBlockLock(uid, user_id)
    })

    this.handleEvent('b:clear_block_lock', ({ uid, user_id }) => {
      clearBlockLock(uid, user_id)
    })

    this.handleEvent('b:clear_user_presence', ({ user_id }) => {
      // Remove all field presence indicators and unlock fields for this user
      document.querySelectorAll(`.field-presence-user[data-user-id="${user_id}"]`)
        .forEach(el => {
          const fieldWrapper = el.closest('.field-wrapper')
          if (fieldWrapper) {
            fieldWrapper.classList.remove('field-locked')
          }
          el.remove()
        })

      // Remove block presence/lock for this user
      clearUserBlockLocks(user_id)
    })

    this.handleEvent('b:set_active_field', (opts) => {
      const color = getPresenceColor(opts.user_id)

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
          // Unlock the old field
          const oldFieldWrapper = otherFieldPresence.closest('.field-wrapper')
          if (oldFieldWrapper) {
            oldFieldWrapper.classList.remove('field-locked')
          }
          otherFieldPresence.remove()
        }
        // create a new presence indicator
        const presence = document.createElement('div')
        presence.setAttribute('data-user-id', opts.user_id)
        presence.setAttribute('data-presence-for', opts.field)
        presence.classList.add('field-presence-user')
        presence.style.setProperty('--presence-color', color)
        // grab the user's avatar from the page presences
        const userAvatar = document.querySelector(
          `.page-presences [data-presence-user-id="${opts.user_id}"] .avatar`
        )

        if (userAvatar) {
          const clonedAvatar = userAvatar.cloneNode(true)
          presence.appendChild(clonedAvatar)
          fieldPresence.appendChild(presence)
          tippy(clonedAvatar, {
            allowHTML: true,
            content: clonedAvatar.dataset.popover,
          })
        }

        // Lock the field wrapper
        const fieldWrapper = fieldPresence.closest('.field-wrapper')
        if (fieldWrapper) {
          fieldWrapper.classList.add('field-locked')
        }
      }
    })
  },

  updated() {
    // Re-assert block locks after form-level patches; block-component
    // patches (which don't bubble here) re-assert in the Block hook
    for (const [uid, userId] of blockLocks) {
      applyBlockLock(uid, userId)
    }
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
