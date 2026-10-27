import { Dom } from '@brandocms/jupiter'
import { bindShortcut } from '../../shortcuts'

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

    // `f` focuses the filter (`filter` in the shortcut registry, which keeps
    // it out of text fields and dialogs)
    this.unbindFilter = bindShortcut('filter', () => {
      const filterInput = this.el.querySelector('.filter input[type="text"]')
      if (!filterInput) return false
      filterInput.focus()
    })

    // Enter in a filter that leaves one entry (`submit_filter`): open it as a
    // click on its row would, so the row says it is opening. A listing whose
    // rows do not link to the entry's editor stays, filtered: its URL takes
    // the filter, as typing it would have.
    this.handleEvent('brando:open_entry', ({ listing, url, patch }) => {
      if (listing !== this.el.id) return
      const link = Array.from(this.el.querySelectorAll('a[data-phx-link="redirect"]')).find(
        a => a.getAttribute('href') === url
      )
      if (link) {
        // LiveView marks only a trusted click's link as loading, and that
        // mark is what `openingRow.js` finds the row by when the navigation
        // starts (its listener runs before this one)
        link.classList.add('phx-click-loading')
        window.addEventListener('phx:page-loading-start', () => link.classList.remove('phx-click-loading'), {
          once: true,
        })
        link.click()
      } else {
        this.js().patch(patch)
      }
    })
  },

  destroyed() {
    Array.from(this.entryLinks).forEach(l =>
      l.removeEventListener('click', this.anchorListener, false)
    )
    this.el.removeEventListener('dragstart', this._rowDragStartHandler, true)
    this.el.removeEventListener('dragend', this._rowDragEndHandler, false)
    this.unbindFilter?.()
    document.body.classList.remove('selection-dragging')
    window.__brandoSelectedIdsDrag = null
  },

  anchorListener(ev) {
    // ev.stopPropagation()
  },
})
