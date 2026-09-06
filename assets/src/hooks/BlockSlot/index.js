import Modal from '../Modal'

export default app => {
  const modal = Modal(app)
  return {
    ...modal,
    focusable() {
      return Array.from(this.el.querySelectorAll(
        'button:not([disabled]):not([tabindex="-1"]), a[href], input:not([disabled]):not([type="hidden"]), textarea:not([disabled]), select:not([disabled]), [contenteditable="true"]'
      )).filter(el => el.getClientRects().length > 0)
    },
    onOpened() {
      modal.onOpened.call(this)
      clearTimeout(this.focusTimer)
      this.focusTimer = setTimeout(() => {
        if (!this.isOpen() || document.activeElement !== this.el) return
        const editor = this.el.querySelector('[contenteditable="true"]')
        ;(editor || this.el.querySelector('.block-slot-done'))?.focus()
      }, 50)
    },
    mounted() {
      modal.mounted.call(this)
      this.slotKeydown = event => {
        // A media dialog can be opened above this drawer. Escape belongs to
        // that dialog until focus returns to the collection.
        if (event.key !== 'Escape' || !this.isOpen() || event.target.closest('[role="dialog"]') !== this.el) return
        event.preventDefault()
        event.stopPropagation()
        this.pushEventTo(this.el, 'close_block_slot', {})
      }
      this.el.addEventListener('keydown', this.slotKeydown)
    },
    destroyed() {
      this.el.removeEventListener('keydown', this.slotKeydown)
      modal.destroyed.call(this)
    },
  }
}
