/**
 * Modal hook — keyboard and screen-reader behaviour for `Content.modal/1`.
 *
 * A modal in the admin is a pre-rendered element that is shown and hidden,
 * either by `JS.show`/`JS.hide` (inline display) or by the server toggling the
 * `visible` class. Neither moves keyboard focus, so before this hook a modal
 * opened with focus still sitting behind it: Tab walked the page underneath,
 * and a screen reader never announced that a dialog had opened.
 *
 * The hook watches for the open/closed transition rather than a LiveView event,
 * because there is no single event to watch — the same modal can be opened by a
 * `JS.show` command on the client or by an assign on the server.
 *
 * It deliberately does not handle Escape: `Content.modal/1` already binds
 * `phx-window-keydown` for that, and its close command is the one that knows
 * whether to hide on the client or tell the server.
 */

// `BrandoAdmin.JSCommands.show_modal/2` fades the dialog in over 200ms; nothing
// inside it has a layout box until that finishes.
const MODAL_TRANSITION_MS = 250

const FOCUSABLE = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])'
].join(',')

export default app => ({
  mounted() {
    this.opener = null
    this.wasOpen = this.isOpen()

    // Tab is handled on the modal itself: the wrap only applies while focus is
    // already inside, and letting it bubble to the document would fight with
    // other keydown handlers on the page.
    this.onKeydown = event => {
      if (event.key !== 'Tab' || !this.isOpen()) return
      this.wrapTab(event)
    }
    this.el.addEventListener('keydown', this.onKeydown)

    // `style` covers JS.show/JS.hide (inline display); `class` covers the
    // server-gated `visible` variant. Watching both means the hook does not
    // need to know which mechanism a given modal uses.
    this.observer = new MutationObserver(() => this.syncOpenState())
    this.observer.observe(this.el, { attributes: true, attributeFilter: ['style', 'class'] })

    if (this.wasOpen) this.onOpened()
  },

  updated() {
    this.syncOpenState()
  },

  destroyed() {
    this.el.removeEventListener('keydown', this.onKeydown)
    this.observer?.disconnect()
    clearTimeout(this.focusTimer)
    // A modal removed from the DOM while open would otherwise strand focus on
    // nothing, dropping the caret back to <body>.
    if (this.wasOpen) this.restoreFocus()
  },

  isOpen() {
    if (this.el.classList.contains('visible')) return true
    // `JS.hide` leaves `display: none` inline; `JS.show` sets it to flex.
    return this.el.style.display !== '' && this.el.style.display !== 'none'
  },

  syncOpenState() {
    const open = this.isOpen()
    if (open === this.wasOpen) return
    this.wasOpen = open
    open ? this.onOpened() : this.restoreFocus()
  },

  onOpened() {
    // Remember who opened it *before* moving focus, so closing returns the user
    // to the control they were on rather than to the top of the page.
    const active = document.activeElement
    this.opener = active && !this.el.contains(active) ? active : this.opener

    // `show_modal/1` reveals the dialog with a 200ms transition, and this runs
    // the instant `display` changes — before its contents have a layout box, so
    // `focusable()` sees nothing. Land on the dialog immediately (which is what
    // names it to a screen reader), then move to the first control once the
    // transition has actually put one on screen.
    this.el.setAttribute('tabindex', '-1')
    this.el.focus()

    clearTimeout(this.focusTimer)
    this.focusTimer = setTimeout(() => {
      if (!this.isOpen()) return
      // Only take focus if it is still on the dialog itself — if the user has
      // already tabbed or clicked somewhere inside, leave them there.
      if (document.activeElement !== this.el) return
      this.focusable()[0]?.focus()
    }, MODAL_TRANSITION_MS)
  },

  restoreFocus() {
    const opener = this.opener
    this.opener = null
    // Only take focus back if it is still inside the modal; if something else
    // has deliberately moved it since, leave it alone.
    if (!this.el.contains(document.activeElement)) return
    if (opener && document.contains(opener)) opener.focus()
  },

  focusable() {
    return Array.from(this.el.querySelectorAll(FOCUSABLE)).filter(
      el => el.offsetParent !== null || el === document.activeElement
    )
  },

  wrapTab(event) {
    const items = this.focusable()
    if (items.length === 0) return

    const first = items[0]
    const last = items[items.length - 1]

    if (event.shiftKey && document.activeElement === first) {
      event.preventDefault()
      last.focus()
    } else if (!event.shiftKey && document.activeElement === last) {
      event.preventDefault()
      first.focus()
    }
  }
})
