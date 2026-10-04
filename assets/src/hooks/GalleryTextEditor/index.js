// The caption / alt text popover under a gallery square. Its inputs are not
// part of the entry form around it (their `form` attribute names no form), so
// Save reads the value here and pushes it to the gallery component.
const OUTSIDE_IGNORED = '#tiptap-link-dialog, .modal, [role="dialog"]:not(.gallery-text-editor)'

export default () => ({
  mounted() {
    this.place()
    this.focus()

    this._onClick = event => {
      if (event.target.closest('[data-gallery-text-save]')) this.save()
      else if (event.target.closest('[data-gallery-text-cancel]')) this.close()
    }
    this._onKeydown = event => {
      if (event.key === 'Escape') {
        event.preventDefault()
        event.stopPropagation()
        this.close()
      } else if (event.key === 'Enter' && !event.shiftKey && event.target.matches('textarea.gallery-text-editor-input')) {
        // Alt text is one line; Enter saves it.
        event.preventDefault()
        this.save()
      } else if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
        event.preventDefault()
        this.save()
      }
    }
    // A click elsewhere closes the popover — but not one in the link dialog
    // its caption editor opens, or in another dialog above it.
    this._onPointerDown = event => {
      if (this.el.contains(event.target)) return
      if (event.target.closest(OUTSIDE_IGNORED)) return
      if (event.target.closest('.gallery-tile-icon')) return
      this.close()
    }
    this._onResize = () => this.place()

    this.el.addEventListener('click', this._onClick)
    this.el.addEventListener('keydown', this._onKeydown)
    document.addEventListener('pointerdown', this._onPointerDown, true)
    window.addEventListener('resize', this._onResize)
  },

  updated() {
    this.place()
  },

  destroyed() {
    document.removeEventListener('pointerdown', this._onPointerDown, true)
    window.removeEventListener('resize', this._onResize)
  },

  // Opens under the square, aligned to its left edge, unless that would run
  // past the gallery or the viewport — then it aligns to the square's right.
  place() {
    const anchor = this.el.parentElement
    if (!anchor) return
    const bounds = (this.el.closest('.gallery-sheet') || document.body).getBoundingClientRect()
    const right = Math.min(bounds.right, document.documentElement.clientWidth - 8)
    const start = anchor.getBoundingClientRect().left
    const flip = start + this.el.offsetWidth > right
    this.js().setAttribute(this.el, 'data-align', flip ? 'end' : 'start')
  },

  focus() {
    const textarea = this.el.querySelector('textarea.gallery-text-editor-input')
    if (textarea) {
      textarea.focus()
      textarea.setSelectionRange(textarea.value.length, textarea.value.length)
      return
    }
    // In the block editor rich text starts as a preview until activated.
    const tiptap = this.el.querySelector('[data-name="TipTap"]')
    if (tiptap) {
      tiptap.dispatchEvent(new Event('brando:tiptap:activate'))
      requestAnimationFrame(() => tiptap.querySelector('[contenteditable="true"]')?.focus())
    }
  },

  value() {
    const textarea = this.el.querySelector('textarea.gallery-text-editor-input')
    if (textarea) return textarea.value
    return this.el.querySelector('.tiptap-text')?.value || ''
  },

  save() {
    let params = {}
    try { params = JSON.parse(this.el.dataset.params || '{}') } catch { params = {} }
    this.pushEventTo(this.el, this.el.dataset.saveEvent, { ...params, value: this.value() })
  },

  close() {
    this.pushEventTo(this.el, this.el.dataset.closeEvent, {})
  },
})
