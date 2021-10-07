import Sortable from 'sortablejs'

export default (app) => ({
  mounted() {
    this.awaitValidation = false

    new Sortable(this.el, {
      animation: 350,
      ghostClass: 'is-sorting',
      swapThreshold: 0.50,
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

    this.pushEventTo(this.el, 'sequenced_subform', { ids: sortedArray }, () => {
      this.awaitValidation = true
    })
  }
})