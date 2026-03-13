import { Dom } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    console.log('[Listing] mounted', this.el.id)

    this.entryLinks = Dom.all(this.el, '.entry-link')
    Array.from(this.entryLinks).forEach(l =>
      l.addEventListener('click', this.anchorListener, false)
    )

    this._rowDragStartHandler = ev => {
      const row = ev.target.closest('.list-row[data-id]')
      if (!row || !this.el.contains(row) || !ev.dataTransfer) return

      const selectedIds = Array.from(
        this.el.querySelectorAll('.list-row.selected[data-id]')
      )
        .map(el => Number(el.dataset.id))
        .filter(Number.isFinite)

      if (selectedIds.length === 0) {
        console.log('[Listing] dragstart ignored, no selected rows')
        return
      }

      ev.dataTransfer.effectAllowed = 'move'
      ev.dataTransfer.setData(
        'application/x-brando-selected-ids',
        JSON.stringify(selectedIds)
      )
      ev.dataTransfer.setData('text/plain', `${selectedIds.length}`)
      window.__brandoSelectedIdsDrag = selectedIds
      console.log('[Listing] dragstart selected ids', selectedIds)

      this.el.classList.add('selection-dragging')
      document.body.classList.add('selection-dragging')
    }

    this._rowDragEndHandler = () => {
      this.el.classList.remove('selection-dragging')
      document.body.classList.remove('selection-dragging')
      window.__brandoSelectedIdsDrag = null
    }

    this.el.addEventListener('dragstart', this._rowDragStartHandler, true)
    this.el.addEventListener('dragend', this._rowDragEndHandler, false)

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
    this.el.removeEventListener('dragstart', this._rowDragStartHandler, true)
    this.el.removeEventListener('dragend', this._rowDragEndHandler, false)
    window.removeEventListener('keydown', this._filterKeyHandler)
    document.body.classList.remove('selection-dragging')
    window.__brandoSelectedIdsDrag = null
  },

  anchorListener(ev) {
    // ev.stopPropagation()
  },
})
