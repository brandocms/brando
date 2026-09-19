import Sortable from 'sortablejs'
import { renumberFootnotes } from '../../components/TipTap/extensions/Footnote'

export default app => ({
  mounted() {
    this.bindSortable()
  },

  bindSortable() {
    let group = this.el.dataset.blocksWrapperType
    let handle = this.el.dataset.sortableHandle || '.sort-handle'
    let isDragging = false
    this.el.addEventListener('focusout', e => isDragging && e.stopImmediatePropagation())
    this.sortable = new Sortable(this.el, {
      group: group ? { name: group, pull: true, put: [group] } : undefined,
      animation: 150,
      handle: handle,
      dragClass: 'drag-item',
      ghostClass: 'is-sorting',
      // Fallback (synthetic mouse) dragging like the other sortable hooks —
      // native HTML5 DnD can't be driven by Playwright in the e2e suite.
      forceFallback: true,
      // The clone that follows the cursor is positioned absolutely against its
      // container, and Sortable measures that container once, at drag start.
      // Left inside the list, the container is whichever ancestor happens to be
      // positioned or transformed, so any scroll or LiveView re-render beneath
      // the drag drifts the clone away from the pointer — the drop indicator
      // stays right, the thing under your hand does not, and the gap reads as
      // the drag skipping several blocks. Anchoring the clone to <body> puts it
      // in page coordinates, where nothing in the editor can shift it.
      fallbackOnBody: true,
      // A few pixels of travel during an ordinary click is not a drag.
      fallbackTolerance: 4,

      onStart: e => (isDragging = true), // prevent phx-blur from firing while dragging
      onEnd: e => {
        isDragging = false
        let params = { old: e.oldIndex, new: e.newIndex, to: {...e.to.dataset}, from: {...e.from.dataset}, ...e.item.dataset }
        this.pushEventTo(this.el, this.el.dataset['drop'] || 'reposition', params)
        renumberFootnotes(this.el)
      }
    })
  }
})
