/**
 * Brando.ModulePickerKeys — the module picker's search field drives the
 * results from the keyboard: ↑↓ moves between the rows shown, Enter inserts
 * the one marked (the first, unless you moved), Escape leaves it to the modal.
 * The mark is `.is-keyboard` on the row, back on the first as results change.
 *
 * It also keeps the "Recently used" list: the modules inserted from this
 * browser, most recent first, sent to the picker when it opens.
 */
const RECENT_KEY = 'brando:recent-modules'
const RECENT_LIMIT = 5

function readRecent() {
  try {
    const ids = JSON.parse(localStorage.getItem(RECENT_KEY) || '[]')
    return Array.isArray(ids) ? ids.filter(id => typeof id === 'string') : []
  } catch {
    return []
  }
}

function remember(id) {
  const ids = [id, ...readRecent().filter(other => other !== id)].slice(0, RECENT_LIMIT * 4)
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify(ids))
  } catch {
    // Private mode or a full store: the list just doesn't grow.
  }
}

export default () => ({
  mounted() {
    this.index = 0
    this.picker = this.el.closest('.module-picker')

    // Stored as the row is chosen: the picker closes in the same patch, so a
    // server round trip would find this hook gone.
    this.onPick = e => {
      const row = e.target.closest('.module-row')
      if (row?.dataset.moduleRef) remember(row.dataset.moduleRef)
    }
    this.picker?.addEventListener('click', this.onPick)

    this.el.addEventListener('keydown', e => {
      const rows = this.rows()
      if (!rows.length) return

      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault()
        const step = e.key === 'ArrowDown' ? 1 : -1
        this.index = Math.max(0, Math.min(rows.length - 1, this.index + step))
        this.mark(rows)
      } else if (e.key === 'Enter') {
        e.preventDefault()
        // Typed fast, the rows may still be for the text before: wait for the
        // server's results for what's in the field, then insert the first.
        if (this.stale()) this.pendingEnter = true
        else this.insert(rows)
      }
    })

    // Typing changes the results; the mark goes back to the first
    this.el.addEventListener('input', () => {
      this.index = 0
    })

    // Picking a group redraws the rows without touching this field, so
    // updated() doesn't run: the mark follows the list itself.
    const results = this.picker?.querySelector('.module-picker-results')
    if (results) {
      this.observer = new MutationObserver(() => {
        this.index = 0
        const rows = this.rows()
        this.mark(rows)
        if (this.pendingEnter && !this.stale()) {
          this.pendingEnter = false
          if (rows.length) this.insert(rows)
        }
      })
      this.observer.observe(results, { childList: true, subtree: true, attributes: true, attributeFilter: ['data-query'] })
    }

    const recent = readRecent()
    if (recent.length) this.pushEventTo(this.el, 'set_recent', { ids: recent })
    this.mark(this.rows())
  },

  updated() {
    this.mark(this.rows())
  },

  destroyed() {
    this.picker?.removeEventListener('click', this.onPick)
    this.observer?.disconnect()
  },

  // The rows shown were rendered for another text than the field holds.
  stale() {
    const results = this.picker?.querySelector('.module-picker-results')
    return !!results && results.dataset.query !== this.el.value
  },

  insert(rows) {
    rows[Math.min(this.index, rows.length - 1)].click()
  },

  rows() {
    return this.picker ? [...this.picker.querySelectorAll('.module-picker-results .module-row')] : []
  },

  mark(rows) {
    if (this.index >= rows.length) this.index = 0
    rows.forEach((row, i) => row.classList.toggle('is-keyboard', i === this.index))
    const marked = rows[this.index]
    if (marked) marked.scrollIntoView({ block: 'nearest' })
  },
})
