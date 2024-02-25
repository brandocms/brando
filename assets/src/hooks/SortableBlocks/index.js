import Sortable from 'sortablejs'

export default app => ({
  mounted() {
    this.bindSortable()
  },

  bindSortable() {
    // this.sortable = new Sortable(this.$blocksWrapper, {
    //   group: this.type,
    //   animation: 150,
    //   ghostClass: 'is-sorting',
    //   sort: true,
    //   handle: `.block-action.move[data-sortable-group=${this.type}]`,
    //   dataIdAttr: 'data-block-index',
    //   draggable: '> [data-phx-component][data-block-uid]',
    //   store: {
    //     get: this.getOrder.bind(this),
    //     set: this.setOrder.bind(this)
    //   }
    // })

    let group = this.el.dataset.blocksWrapperType
    let isDragging = false
    this.el.addEventListener('focusout', e => isDragging && e.stopImmediatePropagation())
    this.sortable = new Sortable(this.el, {
      group: group ? { name: group, pull: true, put: true } : undefined,
      animation: 150,
      handle: '.sort-handle',
      dragClass: 'drag-item',
      ghostClass: 'is-sorting',

      onStart: e => (isDragging = true), // prevent phx-blur from firing while dragging
      onEnd: e => {
        isDragging = false
        let params = { old: e.oldIndex, new: e.newIndex, to: e.to.dataset, ...e.item.dataset }
        this.pushEventTo(this.el, this.el.dataset['drop'] || 'reposition', params)
      }
    })
  }

  // getOrder() {},

  // setOrder() {
  //   let order = this.sortable.toArray().map(Number)
  //   this.pushEventTo(this.el, 'blocks:reorder', { order, type: this.type })
  // }
})
