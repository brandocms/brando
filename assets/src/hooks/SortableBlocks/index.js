import Sortable from 'sortablejs'

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

      onStart: e => (isDragging = true), // prevent phx-blur from firing while dragging
      onEnd: e => {
        isDragging = false
        let params = { old: e.oldIndex, new: e.newIndex, to: {...e.to.dataset}, from: {...e.from.dataset}, ...e.item.dataset }
        this.pushEventTo(this.el, this.el.dataset['drop'] || 'reposition', params)
      }
    })
  }
})
