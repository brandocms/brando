import tippy from 'tippy.js'
import draftRecovery from './draftRecovery'
import locateBlock from './locateBlock'
import dirtyFields from '../../Presence/dirtyFields'
import follow from '../../Presence/follow'
import notes from '../../Notes'
import {
  setFieldPresence,
  clearFieldPresence,
  clearUserPresence,
  getPresenceColor,
} from '../../Presence/fieldPresence'

export default (app) => ({
  mounted() {
    this.skipKeydown = this.el.hasAttribute('data-skip-keydown')
    this.$form = this.el.querySelector('form.main-form')
    this.$input = this.$form.querySelector('input')
    this.submitListenerEvent = this.submitListener.bind(this)
    this.draftRecovery = draftRecovery(this)
    this.stopLocatingBlock = locateBlock(this)
    this.dirtyFields = dirtyFields(this)
    this.follow = follow(this)
    this.notes = notes(this)
    app.notes = this.notes
    // Keep the measurement outside LiveView's patched inline attributes.
    this.toolbarStyle = document.createElement('style')
    document.head.appendChild(this.toolbarStyle)
    this.toolbarStyle.sheet.insertRule(`#${CSS.escape(this.el.id)} {}`)
    const toolbarRule = this.toolbarStyle.sheet.cssRules[0].style
    this.updateToolbarOffset = () => {
      const toolbar = this.el.querySelector('.form-content > .form-tabs')
      if (toolbar !== this.$toolbar) {
        this.toolbarObserver.disconnect()
        this.$toolbar = toolbar
        if (toolbar) this.toolbarObserver.observe(toolbar)
      }
      if (!toolbar) return
      const height = toolbar.getBoundingClientRect().height
      if (!height) return
      const top = parseFloat(getComputedStyle(toolbar).top) || 0
      const offset = `${top + height + 8}px`
      if (toolbarRule.getPropertyValue('--form-toolbar-offset') !== offset) {
        toolbarRule.setProperty('--form-toolbar-offset', offset)
      }
    }
    this.toolbarObserver = new ResizeObserver(this.updateToolbarOffset)
    this.updateToolbarOffset()

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
        this.js().removeClass(drawer, 'hidden x-100')
        this.js().addClass(drawer, 'x-0')
        this.js().show(drawer)
      }
    })

    // Field presence goes through LiveView's sticky JS commands (this.js())
    // so the patcher itself re-applies it after every morphdom pass — plain
    // classList mutations get wiped whenever the block re-renders (e.g. when
    // the other editor's change arrives here).
    this.handleEvent('b:set_active_block', (presence) => {
      const el = setFieldPresence(this.js(), presence)
      this.follow.seen(presence.user_id, el)
    })

    this.handleEvent('b:clear_block_lock', ({ uid, user_id }) => {
      clearFieldPresence(this.js(), uid, user_id)
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

      // Remove block and field presence for this user
      clearUserPresence(this.js(), user_id)
      this.dirtyFields.clearUser(user_id)
      this.follow.left(user_id)
    })

    this.handleEvent('b:set_dirty_fields', ({ user_id, fields, label }) => {
      this.dirtyFields.set(user_id, fields, label)
    })

    this.handleEvent('b:set_active_field', (opts) => {
      const color = getPresenceColor(opts.user_id)

      const fieldPresence = document.querySelector(
        `[data-field-presence="${opts.field}"] .field-presence`
      )

      this.follow.seen(opts.user_id, fieldPresence?.closest('.field-wrapper'))

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

  updated() {
    this.updateToolbarOffset()
    this.dirtyFields.apply()
    this.notes.apply()
  },

  destroyed() {
    this.follow?.destroy()
    this.notes?.destroy()
    if (app.notes === this.notes) app.notes = null
    this.stopLocatingBlock?.()
    this.toolbarObserver?.disconnect()
    this.toolbarStyle?.remove()
    this.draftRecovery?.destroy()
    if (!this.skipKeydown) {
      window.removeEventListener('keydown', this.submitListenerEvent, false)
    }
  },

  disconnected() { this.draftRecovery?.disconnected() },
  reconnected() { this.draftRecovery?.reconnected() },

  // ⇧⌘S saves and closes, ⌘S saves and stays. Ctrl stands in for ⌘ off a
  // Mac, and the key is compared in lower case so Caps Lock doesn't matter.
  submitListener(ev) {
    if (!(ev.metaKey || ev.ctrlKey) || ev.altKey || (ev.key || '').toLowerCase() !== 's') return
    ev.preventDefault()

    const submit = () =>
      this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))

    if (ev.shiftKey) {
      submit()
    } else {
      // Submit once the server has taken the target, not after a guessed delay.
      this.pushEventTo(this.el, 'save_redirect_target', { save_redirect_target: 'self' }, submit)
    }
  },
})
