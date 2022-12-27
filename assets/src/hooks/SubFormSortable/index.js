import Sortable from 'sortablejs'
import { Dom } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    this.awaitValidation = false
    this.embeds = this.el.dataset.embeds

    new Sortable(this.el, {
      animation: 350,
      ghostClass: 'is-sorting',
      swapThreshold: 0.5,
      handle: '.subform-handle',
      draggable: '.subform-entry',
      store: {
        get: this.getOrder.bind(this),
        set: this.setOrder.bind(this)
      }
    })
  },

  updated() {
    if (this.awaitValidation) {
      this.pushEventTo(this.el, 'force_validate')
      this.awaitValidation = false
    }
  },

  getOrder() {
    return []
  },

  setOrder(sortable) {
    const sortedArray = sortable.toArray().map(Number)
    if (this.embeds) {
      this.pushEventTo(
        this.el,
        'sequenced_subform',
        { ids: sortedArray, embeds: this.embeds },
        () => {
          this.awaitValidation = true
        }
      )
    } else {
      this.pushEventTo(this.el, 'sequenced_subform', { ids: sortedArray, embeds: this.embeds })
    }
  }
})
