import { Dom, Events, gsap } from '@brandocms/jupiter'
import tippy from 'tippy.js'

const PRESENCE_COLORS = [
  ['77, 144, 254', 'blue'],     // blue
  ['72, 199, 142', 'green'],    // green
  ['245, 166, 35', 'orange'],   // orange
  ['168, 85, 247', 'purple'],   // purple
  ['239, 68, 68', 'red'],       // red
  ['20, 184, 166', 'teal'],     // teal
]

function getPresenceColorIndex(userId) {
  const els = document.querySelectorAll('.page-presences [data-presence-user-id]')
  const ids = Array.from(els).map(el => el.dataset.presenceUserId)
  const idx = ids.indexOf(String(userId))
  return Math.max(0, idx) % PRESENCE_COLORS.length
}

function getPresenceColor(userId, alpha = 0.6) {
  const [rgb] = PRESENCE_COLORS[getPresenceColorIndex(userId)]
  return `rgba(${rgb}, ${alpha})`
}

function clearBlockPresence(el) {
  el.classList.remove('block-presence-active', 'block-locked')
  el.removeAttribute('data-block-presence-user')
  el.removeAttribute('data-presence-color-index')
  el.style.removeProperty('--presence-color')
  el.style.removeProperty('--presence-color-strong')
  const lockIcon = el.querySelector('.block-lock-icon')
  if (lockIcon) lockIcon.remove()
}

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

    this.handleEvent('b:set_active_block', ({ uid, user_id }) => {
      const colorIdx = getPresenceColorIndex(user_id)
      const color = getPresenceColor(user_id)

      // Remove old block presence from this user
      document.querySelectorAll(`[data-block-presence-user="${user_id}"]`)
        .forEach(clearBlockPresence)

      // Add glow + lock to target block
      const block = document.querySelector(`[data-block-uid="${uid}"] > .block`)
      if (block) {
        block.classList.add('block-presence-active', 'block-locked')
        block.setAttribute('data-block-presence-user', user_id)
        block.setAttribute('data-presence-color-index', colorIdx)
        block.style.setProperty('--presence-color', color)
        block.style.setProperty('--presence-color-strong', getPresenceColor(user_id, 0.8))

        // Add lock icon to block description if not present
        if (!block.querySelector('.block-lock-icon')) {
          const desc = block.querySelector('.block-description')
          if (desc) {
            const lock = document.createElement('div')
            lock.className = 'block-lock-icon'
            lock.style.color = color
            lock.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="14" height="14"><path fill-rule="evenodd" d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z" clip-rule="evenodd" /></svg>'
            desc.prepend(lock)
          }
        }
      }
    })

    this.handleEvent('b:clear_block_lock', ({ uid, user_id }) => {
      const block = document.querySelector(`[data-block-uid="${uid}"] > .block`)
      if (block && block.getAttribute('data-block-presence-user') === String(user_id)) {
        clearBlockPresence(block)
      }
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
      document.querySelectorAll(`[data-block-presence-user="${user_id}"]`)
        .forEach(clearBlockPresence)
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
