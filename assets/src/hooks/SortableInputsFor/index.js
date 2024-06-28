import Sortable from 'sortablejs'

export default app => ({
  mounted() {
    this.target = this.el.dataset.target
    this.sortableSelector = this.el.dataset.sortableSelector
    this.handle = this.el.dataset.sortableHandle
    this.sortableId = this.el.dataset.sortableId
    this.sortableParams = this.el.dataset.sortableParams
    this.sortableBinaryKeys = this.el.dataset.sortableBinaryKeys

    let sorter = new Sortable(this.el, {
      group: this.sortableId,
      animation: 150,
      dragClass: 'drag-item',
      draggable: this.sortableSelector,
      ghostClass: 'is-sorting',
      handle: this.handle,
      swapThreshold: 0.5,
      forceFallback: true,
      onEnd: () => {
        console.log('sortable onEnd —— do nothing')
        // this.el
        //   .closest('form')
        //   .querySelector('input')
        //   .dispatchEvent(new Event('input', { bubbles: true }))
      }
    })
  }
})
