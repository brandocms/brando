import Sortable from 'sortablejs'
import { isEqual } from 'lodash'

export default (app) => ({
  mounted () {
    this.target = this.el.dataset.target
    this.sortableSelector = this.el.dataset.sortableSelector
    this.handle = this.el.dataset.sortableHandle
    this.bindSortable()
  },

  bindSortable () {
    this.sortable = new Sortable(this.el, {
      animation: 150,
      ghostClass: 'is-sorting',
      swapThreshold: 0.50,
      handle: this.handle,
      // TODO: `group` by level? Get from data-group?
      draggable: '.draggable',
      store: {
        get: this.getOrder.bind(this),
        set: this.setOrder.bind(this)
      }
    })
  },

  // updated () {
  //   this.bindSortable()
  //   console.log(this.sortable)
  // },

  getOrder () {
    const items = this.el.querySelectorAll(this.sortableSelector)
    this.currentOrder = Array.from(items).map(r => parseInt(r.dataset.id))
    return []
  },

  setOrder (sortable) {
    const sortedArray = sortable.toArray().map(Number)
    if (!isEqual(this.currentOrder, sortedArray)) {
      this.pushEventTo(this.target, 'sequenced', {
        ids: sortedArray
      })
      this.currentOrder = sortedArray
    }
  }
})