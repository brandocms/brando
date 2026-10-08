/**
 * Brando.CommandPalette — the command palette's keyboard and memory.
 *
 * ⌘K (Ctrl+K off a Mac) opens the palette from any admin screen, and closes
 * it again: `palette` in the shortcut registry (`shortcuts/`), whose capturing
 * `keydown` on the window runs before any editor sees the keys, in text
 * fields too. The sidebar's search row sends `brando:command-palette:open`.
 *
 * A row with `data-palette-command` runs a command instead of opening a page:
 * "Keyboard shortcuts" opens the shortcut sheet.
 *
 * The dialog is a native modal `<dialog>`: the page under it is inert while
 * it is open, Escape closes it, and focus goes back to where it was.
 *
 * ↑/↓ move the selection, ↵ opens the selected row, ⌘↵ (Ctrl+↵) opens it in
 * a new tab. The server renders the rows; the selection is client state, set
 * with sticky JS commands so LiveView patches keep it. Pressing ↵ before the
 * results for the text in the field have arrived waits for them, as the
 * module picker does.
 *
 * Recent places: every admin page visited is remembered in localStorage, per
 * user and site, and sent to the server when the palette opens.
 */
import { bindShortcut } from '../../shortcuts'

const RECENT_LIMIT = 12

export default () => ({
  mounted() {
    this.dialog = this.el.querySelector('dialog')
    this.input = this.el.querySelector('#command-palette-input')
    this.results = this.el.querySelector('#command-palette-results')
    this.index = 0
    this.query = this.results.dataset.query
    this.pendingEnter = null
    this.restoreFocus = true

    this.unbindShortcut = bindShortcut('palette', () => {
      if (this.dialog.open) this.close()
      else this.open()
    })

    this.onOpenRequest = () => this.open()
    this.el.addEventListener('brando:command-palette:open', this.onOpenRequest)

    this.input.addEventListener('keydown', e => this.onKey(e))

    this.dialog.addEventListener('click', e => {
      // A click on the backdrop lands on the dialog itself
      if (e.target === this.dialog || e.target.closest('[data-palette-close]')) {
        this.close()
        return
      }
      const item = e.target.closest('[data-palette-item]')
      if (!item) return
      if (item.dataset.paletteCommand) {
        this.runCommand(item)
        return
      }
      // A modified click opens a tab: the page stays, and so does the focus
      const newTab = e.metaKey || e.ctrlKey || e.shiftKey || e.button === 1
      this.close({ restoreFocus: newTab })
    })

    this.dialog.addEventListener('mousemove', e => {
      const item = e.target.closest('[data-palette-item]')
      if (!item) return
      const index = this.items().indexOf(item)
      if (index > -1 && index !== this.index) {
        this.index = index
        this.mark(false)
      }
    })

    this.dialog.addEventListener('close', () => {
      const opener = this.opener
      this.opener = null
      this.pendingEnter = null
      this.pushEvent('close', {})
      if (this.restoreFocus && opener && opener.isConnected && typeof opener.focus === 'function') {
        opener.focus({ preventScroll: true })
      }
    })

    // The rows change under us: new results, or a patch. The selection goes
    // back to the first row only when the results are for another query.
    this.observer = new MutationObserver(() => this.sync())
    this.observer.observe(this.results, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['data-query'],
    })

    this.onPage = e => {
      if (['initial', 'redirect', 'patch'].includes(e.detail?.kind)) this.rememberSoon()
    }
    window.addEventListener('phx:page-loading-stop', this.onPage)
    this.rememberSoon()
  },

  destroyed() {
    this.unbindShortcut?.()
    window.removeEventListener('phx:page-loading-stop', this.onPage)
    this.observer?.disconnect()
    clearTimeout(this.rememberTimer)
  },

  open() {
    if (this.dialog.open) return
    this.opener = document.activeElement
    this.restoreFocus = true
    this.input.value = ''
    this.index = 0
    this.dialog.showModal()
    this.input.focus()
    this.pushEvent('open', { recent: this.readRecent(), path: window.location.pathname })
  },

  close({ restoreFocus = true } = {}) {
    if (!this.dialog.open) return
    this.restoreFocus = restoreFocus
    this.dialog.close()
  },

  onKey(e) {
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault()
      const items = this.items()
      if (!items.length) return
      const step = e.key === 'ArrowDown' ? 1 : -1
      this.index = (this.index + step + items.length) % items.length
      this.mark(true)
    } else if (e.key === 'Enter') {
      e.preventDefault()
      const newTab = e.metaKey || e.ctrlKey
      // Typed fast, the rows may still be for the text before
      if (this.stale()) this.pendingEnter = { newTab }
      else this.activate(newTab)
    }
  },

  activate(newTab) {
    const item = this.items()[this.index]
    if (!item) return

    if (item.dataset.paletteCommand) {
      this.runCommand(item)
      return
    }

    if (newTab) {
      window.open(item.href, '_blank', 'noopener')
      this.close()
    } else {
      this.close({ restoreFocus: false })
      // The row is a LiveView link: clicking it navigates in place
      item.click()
    }
  },

  // The palette closes and hands the place it was opened from to what the
  // command opens, which gives the focus back there when it closes.
  runCommand(item) {
    const opener = this.opener
    this.close({ restoreFocus: false })
    if (item.dataset.paletteCommand === 'shortcuts') {
      document.getElementById('shortcut-sheet')?.dispatchEvent(new CustomEvent('brando:shortcuts:open', { detail: { opener } }))
    }
  },

  stale() {
    return this.results.dataset.query !== this.input.value
  },

  sync() {
    if (this.results.dataset.query !== this.query) {
      this.query = this.results.dataset.query
      this.index = 0
    }
    this.mark(false)

    if (this.pendingEnter && !this.stale()) {
      const { newTab } = this.pendingEnter
      this.pendingEnter = null
      this.activate(newTab)
    }
  },

  items() {
    return Array.from(this.results.querySelectorAll('[data-palette-item]'))
  },

  mark(scroll) {
    const items = this.items()
    if (this.index >= items.length) this.index = 0
    const js = this.js()

    items.forEach((item, i) => {
      const active = i === this.index
      if (active) js.addClass(item, 'is-active')
      else js.removeClass(item, 'is-active')
      js.setAttribute(item, 'aria-selected', String(active))
    })

    const current = items[this.index]
    if (current) {
      js.setAttribute(this.input, 'aria-activedescendant', current.id)
      if (scroll) current.scrollIntoView({ block: 'nearest' })
    } else {
      js.removeAttribute(this.input, 'aria-activedescendant')
    }
  },

  // Recent places, per user and site

  storageKey() {
    return `brando:command-palette:recent:${this.el.dataset.user || 'anonymous'}:${this.el.dataset.site || 'default'}`
  },

  readRecent() {
    try {
      const places = JSON.parse(localStorage.getItem(this.storageKey()) || '[]')
      return Array.isArray(places) ? places.filter(p => p && typeof p.path === 'string') : []
    } catch {
      return []
    }
  },

  // Stored at once, so a page left quickly still counts, and again a moment
  // later in case the page's render changed its title.
  rememberSoon() {
    this.remember()
    clearTimeout(this.rememberTimer)
    this.rememberTimer = setTimeout(() => this.remember(), 300)
  },

  remember() {
    const { pathname, search } = window.location
    if (!pathname.startsWith('/admin') || /^\/admin\/(login|logout|access-denied)/.test(pathname)) return

    // "Sommerro — Case | Brando" → "Sommerro — Case"
    const title = document.title.replace(/\s+\|[^|]*$/, '').trim()
    const place = { path: pathname + search, title }
    const places = [place, ...this.readRecent().filter(p => p.path.split('?')[0] !== pathname)].slice(0, RECENT_LIMIT)

    try {
      localStorage.setItem(this.storageKey(), JSON.stringify(places))
    } catch {
      // Private mode or a full store: the list just doesn't grow.
    }
  },
})
