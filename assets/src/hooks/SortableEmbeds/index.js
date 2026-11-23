import Sortable from 'sortablejs'

export default (app) => ({
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
      draggable: this.sortableSelector || '.draggable',
      ghostClass: 'is-sorting',
      handle: this.handle,
      swapThreshold: 0.5,
      forceFallback: true,
      onEnd: (e) => {
        // A row dropped where it stood changed nothing. Sending it would put
        // this browser's list over one another editor has changed meanwhile.
        if (e.from === e.to && e.oldIndex === e.newIndex) return

        // On the moved row's sort input, so the change names the list's
        // sort param and the form sends the new order to other editors.
        // A row without one changes the form as a whole.
        const changed =
          e.item.querySelector(':scope > [data-sort-input]') ||
          this.el.closest('form')?.querySelector('input')
        changed?.dispatchEvent(new Event('input', { bubbles: true }))

        let params = {
          old: e.oldIndex,
          new: e.newIndex,
          to: e.to.dataset,
          ...e.item.dataset,
        }
        this.pushEventTo(
          this.el,
          this.el.dataset['drop'] || 'reposition',
          params
        )
      },
    })
  },
})
