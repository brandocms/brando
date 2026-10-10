import tippy from 'tippy.js'
import draftRecovery from './draftRecovery'
import saveForm from './saveForm'
import { matches } from '../../shortcuts/registry'
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
    // A block name too long for its header ends in an ellipsis (Block.css);
    // hovering it shows it whole. Set as it is hovered, so a patch that drops
    // the title costs nothing and the next hover has the current name.
    this.onBlockNameHover = event => {
      const name = event.target.closest?.('.block-toolbar .block-name')
      if (!name) return
      const text = name.scrollWidth > name.clientWidth ? name.textContent.replace(/\s+/g, ' ').trim() : ''
      if (text && name.title !== text) name.title = text
      else if (!text && name.hasAttribute('title')) name.removeAttribute('title')
    }
    this.el.addEventListener('mouseover', this.onBlockNameHover)

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
    this.observeStuckToolbar()

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
      this.releaseField(`[data-user-id="${CSS.escape(String(user_id))}"]`)

      // Remove block and field presence for this user
      clearUserPresence(this.js(), user_id)
      this.dirtyFields.clearUser(user_id)
      this.follow.left(user_id)
    })

    this.handleEvent('b:set_dirty_fields', ({ user_id, fields, label }) => {
      this.dirtyFields.set(user_id, fields, label)
    })

    // Another editor's tab moved to an entry field, which is locked for us
    // while they are in it, or left it (`field` is null), which releases it.
    // Locks are per tab: one editor can be in two fields from two tabs.
    this.handleEvent('b:set_active_field', (opts) => {
      const tab = opts.tab
        ? `[data-tab="${CSS.escape(String(opts.tab))}"]`
        : `[data-user-id="${CSS.escape(String(opts.user_id))}"]`

      if (!opts.field) {
        this.releaseField(tab)
        return
      }

      const color = getPresenceColor(opts.user_id)

      const fieldPresence = document.querySelector(
        `[data-field-presence="${opts.field}"] .field-presence`
      )

      this.follow.seen(opts.user_id, fieldPresence?.closest('.field-wrapper'))

      if (fieldPresence) {
        // the field this tab was in before
        const otherFieldPresence = document.querySelector(`.field-presence-user${tab}`)

        if (otherFieldPresence) {
          // if it's presence indicator for the same field, just return
          const otherFieldPresenceFor =
            otherFieldPresence.getAttribute('data-presence-for')
          if (otherFieldPresenceFor === opts.field) {
            return
          }
          this.releaseField(tab)
        }
        // create a new presence indicator
        const presence = document.createElement('div')
        presence.setAttribute('data-user-id', opts.user_id)
        if (opts.tab) presence.setAttribute('data-tab', opts.tab)
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

  // Removes the avatars matching `selector` (a tab's, or all of a user's)
  // from the entry fields they were in, and unlocks a field nobody else is
  // in.
  releaseField(selector) {
    document.querySelectorAll(`.field-presence-user${selector}`)
      .forEach(el => {
        const fieldWrapper = el.closest('.field-wrapper')
        el.remove()
        if (fieldWrapper && !fieldWrapper.querySelector('.field-presence-user')) {
          this.js().removeClass(fieldWrapper, 'field-locked')
        }
      })
  },

  updated() {
    this.draftRecovery?.updated()
    this.updateToolbarOffset()
    this.observeStuckToolbar()
    this.dirtyFields.apply()
    this.notes.apply()
  },

  destroyed() {
    this.trackOfflineEdits(false)
    this.follow?.destroy()
    this.notes?.destroy()
    this.el.removeEventListener('mouseover', this.onBlockNameHover)
    if (app.notes === this.notes) app.notes = null
    this.stopLocatingBlock?.()
    this.toolbarObserver?.disconnect()
    this.stuckObserver?.disconnect()
    this.toolbarStyle?.remove()
    this.draftRecovery?.destroy()
    if (!this.skipKeydown) {
      window.removeEventListener('keydown', this.submitListenerEvent, false)
    }
  },

  // The entry toolbar is sticky. Once it sticks, content scrolls under the
  // gap between its tabs and its tools, so the bar takes a page-coloured band
  // (`is-stuck`, Form.css). The sentinel just above the bar crosses the bar's
  // sticky `top` exactly when the bar sticks. The class goes through
  // `this.js()` so LiveView patches keep it.
  observeStuckToolbar() {
    const sentinel = this.el.querySelector('.form-content > .form-tabs-sentinel')
    if (sentinel === this.$stuckSentinel) return
    this.stuckObserver?.disconnect()
    this.$stuckSentinel = sentinel
    const toolbar = sentinel?.nextElementSibling
    if (!toolbar?.classList.contains('form-tabs')) return
    const top = parseFloat(getComputedStyle(toolbar).top) || 0
    this.stuckObserver = new IntersectionObserver(([entry]) => {
      const bar = this.$stuckSentinel?.nextElementSibling
      if (!bar) return
      const line = entry.rootBounds ? entry.rootBounds.top : top + 1
      const stuck = !entry.isIntersecting && entry.boundingClientRect.top < line
      if (stuck === bar.classList.contains('is-stuck')) return
      if (stuck) this.js().addClass(bar, 'is-stuck')
      else this.js().removeClass(bar, 'is-stuck')
    }, { rootMargin: `-${top + 1}px 0px 0px 0px` })
    this.stuckObserver.observe(sentinel)
  },

  disconnected() {
    this.draftRecovery?.disconnected()
    this.trackOfflineEdits(true)
  },
  reconnected() {
    this.draftRecovery?.reconnected()
    this.trackOfflineEdits(false)
  },

  // The entry inputs typed into while the socket is down are listed in the
  // form itself (`__offline_edits`), so LiveView's recovery of the form
  // after the reconnect carries the list: the server takes those fields as
  // fresh edits, and the rest of the recovered form as what it was
  // (`recover_form` in form.ex).
  trackOfflineEdits(on) {
    if (this.onOfflineInput) {
      this.$form.removeEventListener('input', this.onOfflineInput, true)
      this.$form.removeEventListener('change', this.onOfflineInput, true)
      this.onOfflineInput = null
    }
    if (!on) return

    const edits = new Set()
    this.$form.querySelector(':scope > input[name="__offline_edits"]')?.remove()
    this.onOfflineInput = event => {
      const name = event.target?.name
      if (!name || name === '__offline_edits' || event.target.form !== this.$form) return
      edits.add(name)
      let list = this.$form.querySelector(':scope > input[name="__offline_edits"]')
      if (!list) {
        list = document.createElement('input')
        list.type = 'hidden'
        list.name = '__offline_edits'
        this.$form.appendChild(list)
      }
      list.value = [...edits].join(' ')
    }
    this.$form.addEventListener('input', this.onOfflineInput, true)
    this.$form.addEventListener('change', this.onOfflineInput, true)
  },

  // ⇧⌘S saves and closes, ⌘S saves and stays. Ctrl stands in for ⌘ off a
  // Mac, and the key is compared in lower case so Caps Lock doesn't matter.
  // ⌘S saves and stays, ⇧⌘S saves and closes (`save` and `save-close` in
  // the shortcut registry, which the shortcut sheet lists).
  submitListener(ev) {
    if (!matches('save', ev) && !matches('save-close', ev)) return
    ev.preventDefault()

    // The entry form saves without a form submit, which would take the focus
    // from what is being typed in, and says in the same push whether to stay
    // (`saveForm.js`).
    if (this.$form.dataset.saveEvent) {
      saveForm(this, this.$form, { stay: !ev.shiftKey })
      return
    }

    const submit = () => saveForm(this, this.$form)

    if (ev.shiftKey) {
      submit()
    } else {
      // Submit once the server has taken the target, not after a guessed delay.
      this.pushEventTo(this.el, 'save_redirect_target', { save_redirect_target: 'self' }, submit)
    }
  },
})
