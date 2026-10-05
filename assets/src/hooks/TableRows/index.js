// The rows of an inline subform, a table block or a variable list: a row added with Insert or
// Add fades in, tinted for a moment, so the eye finds it.
//
// Rows are keyed by position, so after an insert the server patches the
// existing row elements with shifted content and adds one at the end. The new
// row is the one at the clicked position, whichever element now holds it.
// The Web Animations API leaves no inline style for a patch to strip.
const ROWS = ':scope :is(.subform-table-body, .vars-list-body) > :is(.subform-entry, .table-row)'

export default () => ({
  mounted() {
    this.pending = null

    this.onClick = (event) => {
      const button = event.target.closest('.subform-insert, .add-entry-button')
      if (!button || !this.el.contains(button)) return

      const rows = this.rows()
      const row = button.closest('.subform-entry, .table-row')
      this.pending = { index: row ? rows.indexOf(row) : rows.length, count: rows.length }
    }

    this.observer = new MutationObserver(() => this.reveal())
    this.observer.observe(this.el, { childList: true, subtree: true })
    this.el.addEventListener('click', this.onClick)
  },

  destroyed() {
    this.observer.disconnect()
    this.el.removeEventListener('click', this.onClick)
  },

  rows() {
    return [...this.el.querySelectorAll(ROWS)]
  },

  reveal() {
    if (!this.pending) return

    const rows = this.rows()
    if (rows.length <= this.pending.count) return

    const row = rows[this.pending.index]
    this.pending = null
    if (!row || window.matchMedia('(prefers-reduced-motion: reduce)').matches) return

    row.animate(
      [
        { opacity: 0, backgroundColor: '#e8f1e5' },
        { opacity: 1, backgroundColor: '#e8f1e5', offset: 0.35 },
        { opacity: 1, backgroundColor: 'transparent' }
      ],
      { duration: 900, easing: 'ease-out' }
    )
  }
})
