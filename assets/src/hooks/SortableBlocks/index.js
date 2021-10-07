import { Dom, gsap } from '@brandocms/jupiter'
import autosize from 'autosize'
import Sortable from 'sortablejs'

export default (app) => ({
  mounted() {
    this.bindSortable()
  },

  bindSortable() {
    this.$blocksWrapper = this.el
    this.type = this.el.dataset.blocksWrapperType

    this.sortable = new Sortable(this.$blocksWrapper, {
      group: this.type,
      animation: 150,
      ghostClass: 'is-sorting',
      sort: true,
      handle: `.block-action.move[data-sortable-group=${this.type}]`,
      dataIdAttr: 'data-block-index',
      draggable: '> [data-phx-component][data-block-uid]',
      store: {
        get: this.getOrder.bind(this),
        set: this.setOrder.bind(this)
      }
    })
  },

  getOrder() {

  },

  setOrder() {
    let order = this.sortable.toArray().map(Number)
    this.pushEventTo(this.el, 'blocks:reorder', { order, type: this.type })
  }
})