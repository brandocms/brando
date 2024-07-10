import Sortable from 'sortablejs'

export default app => ({
  mounted() {
    this.target = this.el.dataset.target
    this.sortableSelector = this.el.dataset.sortableSelector
    this.handle = this.el.dataset.sortableHandle
    this.sortableId = this.el.dataset.sortableId
    this.sortableParams = this.el.dataset.sortableParams
    this.sortableBinaryKeys = this.el.dataset.sortableBinaryKeys
    this.sortableDispatchEvent = this.el.dataset.sortableDispatchEvent
    this.sortableDispatchEventTargetId = this.el.dataset.sortableDispatchEventTargetId
    this.sortablePushEvent = this.el.dataset.sortablePushEvent
    this.sortableFilter = this.el.dataset.sortableFilter

    let sorter = new Sortable(this.el, {
      group: this.sortableId,
      animation: 150,
      dragClass: 'drag-item',
      draggable: this.sortableSelector || '.draggable',
      ghostClass: 'is-sorting',
      handle: this.handle,
      filter: this.sortableFilter,
      swapThreshold: 0.5,
      forceFallback: true,
      onEnd: e => {
        if (this.sortableDispatchEvent) {
          let target
          if (this.sortableDispatchEventTargetId) {
            // TODO: set debounce to 0, then back again after dispatching event
            target = document.getElementById(this.sortableDispatchEventTargetId)
          } else {
            target = this.el.closest('form').querySelector('input')
          }
          target.dispatchEvent(new Event('input', { bubbles: true }))
        }

        if (this.sortablePushEvent) {
          let params = { old: e.oldIndex, new: e.newIndex, to: e.to.dataset, ...e.item.dataset }
          this.pushEventTo(this.el, this.el.dataset['drop'] || 'reposition', params)
        }
      }
    })
  }
})
