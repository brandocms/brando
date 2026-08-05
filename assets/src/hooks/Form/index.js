import { Dom, Events, gsap } from '@brandocms/jupiter'
import tippy from 'tippy.js'
import {
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

    this.claimDeliverTopic()

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

    // Lock decorations go through LiveView's sticky JS commands (this.js())
    // so the patcher itself re-applies them after every morphdom pass —
    // plain classList mutations get wiped whenever a locked block
    // re-renders (e.g. when its owner's shipped edit applies here).
    this.handleEvent('b:set_active_block', ({ uid, user_id }) => {
      setBlockLock(this.js(), uid, user_id)
    })

    this.handleEvent('b:clear_block_lock', ({ uid, user_id }) => {
      clearBlockLock(this.js(), uid, user_id)
    })

    this.handleEvent('b:clear_user_presence', ({ user_id }) => {
      // Remove all field presence indicators and unlock fields for this user
      document.querySelectorAll(`.field-presence-user[data-user-id="${user_id}"]`)
        .forEach(el => {
          const fieldWrapper = el.closest('.field-wrapper')
          if (fieldWrapper) {
            this.js().removeClass(fieldWrapper, 'field-locked')
          }
          el.remove()
        })

      // Remove block presence/lock for this user
      clearUserBlockLocks(this.js(), user_id)
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
            this.js().removeClass(oldFieldWrapper, 'field-locked')
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

        // Lock the field wrapper — sticky: the form re-renders on every
        // validate and a plain classList.add would be wiped by the patch
        const fieldWrapper = fieldPresence.closest('.field-wrapper')
        if (fieldWrapper) {
          this.js().addClass(fieldWrapper, 'field-locked')
        }
      }
    })
  },

  /**
   * Own the asset-delivery topic on the client so it survives a form remount.
   *
   * The server mints `deliver_topic` in `mount/1`, so every remount produced a
   * NEW topic while an upload already in flight kept the OLD one — the sticky
   * UploadManager survives live navigation, so it would broadcast the finished
   * asset to a topic nobody was listening on any more, silently. Measured:
   * two mounts of the same form gave `form:a852c2d1-…` and `form:dae79cd2-…`.
   *
   * The key is scoped by ENTRY, not just by `el.id`. `el.id` is
   * `project_form-el` for every project, so a tab-wide topic keyed on it alone
   * would hand project A's upload to project B's form — the same cross-entry
   * leak as the block-recovery key (see BlockField, which scopes the same way).
   * `sessionStorage` is per-tab, which is exactly the other constraint: two
   * tabs editing one entry must not share a topic.
   */
  claimDeliverTopic() {
    const entryId = this.el.dataset.entryId || 'new'
    const key = `brando:deliver-topic:${entryId}:${this.el.id}`

    let topic = sessionStorage.getItem(key)

    if (!topic) {
      topic = `form:${crypto.randomUUID()}`
      sessionStorage.setItem(key, topic)
    }

    // Set it locally first: the upload triggers resolve their delivery target
    // by reading this attribute off the closest ancestor, so it has to be right
    // before any upload can start — not one round-trip later. The server
    // assigns the same value back, so the next patch re-renders it unchanged.
    this.el.dataset.deliverTopic = topic
    // pushEventTo, not pushEvent: the handler lives on the Form LiveComponent,
    // and a bare pushEvent would go to the parent LiveView. Same pattern as
    // BlockField's recover_blocks.
    this.pushEventTo(this.el, 'set_deliver_topic', { topic })
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
