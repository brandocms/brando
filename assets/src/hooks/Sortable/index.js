import Sortable from 'sortablejs'
import { isEqual } from 'lodash'

export default (app) => ({
  mounted () {
    this.target = this.el.dataset.target
    this.sortableSelector = this.el.dataset.sortableSelector
    this.handle = this.el.dataset.sortableHandle
    this.sortableId = this.el.dataset.sortableId
    this.sortableParams = this.el.dataset.sortableParams    
    this.bindSortable()
  },

  bindSortable () {
    this.sortable = new Sortable(this.el, {
      group: this.sortableId,
      animation: 150,
      ghostClass: 'is-sorting',
      swapThreshold: 0.50,
      handle: this.handle,
      draggable: '.draggable',
      store: {
        get: this.getOrder.bind(this),
        set: this.setOrder.bind(this)
      }
    })
  },

  getOrder () {
    const items = this.el.querySelectorAll(this.sortableSelector)
    this.currentOrder = Array.from(items).map(r => parseInt(r.dataset.id))
    return []
  },

  setOrder (sortable) {
    this.sortableOffset = this.el.dataset.sortableOffset || 0
    const sortedArray = sortable.toArray().map(Number)
    if (!isEqual(this.currentOrder, sortedArray)) {
      if (this.target) {
        this.pushEventTo(this.target, 'sequenced', { 
          ids: sortedArray, 
          sortable_id: this.sortableId, 
          sortable_params: this.sortableParams,
          sortable_offset: this.sortableOffset
        })
      } else {
        this.pushEvent('sequenced', { 
          ids: sortedArray, 
          sortable_id: this.sortableId,
          sortable_params: this.sortableParams,
          sortable_offset: this.sortableOffset
        })
      }
      this.currentOrder = sortedArray
    }
  }
})