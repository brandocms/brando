import { Dom } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.entryLinks = Dom.all(this.el, '.entry-link')
    Array.from(this.entryLinks).forEach(l =>
      l.addEventListener('click', this.anchorListener, false)
    )

    this._filterKeyHandler = ev => {
      if (
        ev.key === 'f' &&
        !ev.target.matches('input, textarea, select, [contenteditable]')
      ) {
        const filterInput = this.el.querySelector(
          '.filter input[type="text"]'
        )
        if (filterInput) {
          ev.preventDefault()
          filterInput.focus()
        }
      }
    }
    window.addEventListener('keydown', this._filterKeyHandler)
  },

  destroyed() {
    Array.from(this.entryLinks).forEach(l =>
      l.removeEventListener('click', this.anchorListener, false)
    )
    window.removeEventListener('keydown', this._filterKeyHandler)
  },

  anchorListener(ev) {
    // ev.stopPropagation()
  }
})
