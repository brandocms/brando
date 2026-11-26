/**
 * Block modules → Release changes (`BrandoAdmin.Content.ReleaseChangesLive`).
 *
 * Brando.ReleasePreview — one side of the before/after preview. The iframe
 * renders the site's own template (`/__livepreview?key=…`) in a sandbox, so
 * it posts the blocks to mark to the page's script instead
 * (`livepreview_highlight.js`): changed blocks get an amber outline, failed
 * ones a red one, each with its module's name. The page is laid out at the
 * viewport's real width and scaled down to the pane.
 *
 *   data-viewport  mobile (390), tablet (820) or desktop (1366)
 *   data-marks     JSON [{uid, kind: 'changed' | 'failed', label}], [] for none
 *   data-focus     a block uid to scroll to
 *
 * Brando.ReleaseDialog — the apply confirmation, a native <dialog> the view
 * opens and closes with `data-open`, with the shared dialog motion
 * (`nativeDialogMotion.js`); Esc and the backdrop tell the view (`data-close`).
 *
 * Brando.ReleaseChanges — the preview's frame: Esc leaves full screen, and
 * `release:copy` puts a shared preview link on the clipboard.
 */
import { openDialog, closeDialog, resetDialog, onDialogClose, isBackdropClick } from '../../nativeDialogMotion'

const WIDTHS = { mobile: 390, tablet: 820, desktop: 1366 }

export const ReleasePreview = () => ({
  mounted() {
    this.fit()
    this.resizeObserver = new ResizeObserver(() => this.fit())
    this.resizeObserver.observe(this.el.parentElement)
    this.onLoad = () => this.mark(true)
    this.el.addEventListener('load', this.onLoad)
    // The page asks to load again (`reloadPage` in livepreview.js). Its
    // origin is opaque, so it is matched by its source.
    this.onMessage = event => {
      if (event.source !== this.el.contentWindow) return
      if (event.data?.source === 'brando-live-preview' && event.data.type === 'reload') {
        this.el.src = this.el.getAttribute('src')
      }
    }
    window.addEventListener('message', this.onMessage)
  },

  updated() {
    this.fit()
    this.mark(this.el.dataset.focus !== this.focus)
  },

  destroyed() {
    this.el.removeEventListener('load', this.onLoad)
    window.removeEventListener('message', this.onMessage)
    this.resizeObserver?.disconnect()
  },

  fit() {
    const box = this.el.parentElement
    const width = WIDTHS[this.el.dataset.viewport] || WIDTHS.desktop
    const available = Math.max(box.clientWidth - 32, 120)
    const scale = Math.min(1, available / width)
    const full = this.el.dataset.full === 'true'
    const height = full ? Math.max(box.clientHeight - 32, 200) / scale : Math.round(width * (this.el.dataset.viewport === 'mobile' ? 2 : 1.2))
    Object.assign(this.el.style, {
      width: `${width}px`,
      height: `${height}px`,
      transform: `scale(${scale})`,
      transformOrigin: 'top left',
      marginRight: `${width * scale - width}px`,
      marginBottom: `${height * scale - height}px`,
    })
    if (!full) box.style.height = `${height * scale + 32}px`
    else box.style.height = ''
  },

  // The page's origin is opaque, so the message goes to any origin: it holds
  // block uids and module names, and the page checks it comes from this window.
  mark(scroll) {
    let marks = []
    try { marks = JSON.parse(this.el.dataset.marks || '[]') } catch (_) { marks = [] }
    this.focus = this.el.dataset.focus
    this.el.contentWindow?.postMessage(
      {
        source: 'brando-admin',
        type: 'highlight',
        uids: marks.map(mark => mark.uid),
        marks,
        show: marks.length > 0,
        scroll,
        focus: this.focus || null,
      },
      '*'
    )
  },
})

export const ReleaseDialog = () => ({
  mounted() {
    this.dialog = this.el
    this.close = () => this.pushEvent(this.el.dataset.close, {})
    this.onCancel = event => {
      event.preventDefault()
      this.close()
    }
    this.onClick = event => {
      if (isBackdropClick(event, this.el)) this.close()
    }
    this.el.addEventListener('cancel', this.onCancel)
    this.el.addEventListener('click', this.onClick)
    onDialogClose(this, () => resetDialog(this))
    this.sync()
  },

  updated() {
    this.sync()
  },

  destroyed() {
    clearTimeout(this.closeTimer)
    this.el.removeEventListener('cancel', this.onCancel)
    this.el.removeEventListener('click', this.onClick)
  },

  sync() {
    const open = this.el.dataset.open === 'true'
    if (open && (!this.el.open || this.closing)) {
      openDialog(this)
      this.el.querySelector('[autofocus]')?.focus()
    } else if (!open) {
      closeDialog(this)
    }
  },
})

export const ReleaseChanges = () => ({
  mounted() {
    this.onKey = event => {
      if (event.key === 'Escape' && this.el.classList.contains('release-preview-full')) {
        this.pushEvent('full_screen', { on: 'false' })
      }
    }
    window.addEventListener('keydown', this.onKey)
    this.handleEvent('release:copy', ({ text }) => {
      navigator.clipboard?.writeText(text).catch(() => {})
    })
  },

  destroyed() {
    window.removeEventListener('keydown', this.onKey)
  },
})
