import { prefersReducedMotion } from '../../motion'

// A `:string_list` input (Input.input/1). The server renders one text input
// per value plus an empty one, named `field[]` with positional ids. Insert and
// remove change the rows here; the form's next change then carries the list in
// its new order, and the server renders the same rows back.
//
// With `data-sync-insert` (a form whose view keeps blank rows and renders them
// back), an inserted row sends the form's change at once, past the input's
// debounce: the form is locked until the reply, so a render already on its way
// cannot land on the shifted rows. Elsewhere the blank row is not rendered
// back, so an insert sends nothing until something is typed in it.
//
// Until then the row is pending, and a patch of the list from another change
// (another field, another editor's field sync) draws only the server's rows.
// A pending row's input has an id of its own, not a position, and the other
// rows are numbered without it, so their ids are the ones the server draws.
// The pending rows are taken out before the patch, which then lands on the
// rows it draws, and put back after it between the same server rows. A row
// stops being pending when it is typed in or removed, when the form is saved,
// when the server draws it itself (it holds the blank row in its params), or
// when the patch changes the server's rows (another value, a restored
// revision).
//
// Ids are renumbered after each change: when the server's render arrives,
// every row is patched in place and the focused one keeps its focus.

// The rows of `el` that hold a value, the empty last row left out
const valueRows = (el) => [...el.querySelectorAll(':scope > .string-list-row:not(.string-list-add)')]

// What the server last drew in the row, not what has been typed in it since
const serverValue = (row) => row.querySelector('input').getAttribute('value') ?? ''

const startsWith = (list, prefix) => prefix.every((value, index) => list[index] === value)

export default () => ({
  mounted() {
    // pending row → its input's client id
    this.pending = new Map()
    this.inserted = 0

    this.onClick = (event) => {
      const insert = event.target.closest('.string-list-insert')
      const remove = event.target.closest('.string-list-remove')
      if (insert) this.insertAt(insert.closest('.string-list-row'))
      if (remove) this.remove(remove.closest('.string-list-row'))
    }
    this.onInput = (event) => {
      if (this.pending.delete(event.target.closest('.string-list-row'))) this.renumber()
    }
    this.onSave = () => this.settle()

    this.el.addEventListener('click', this.onClick)
    this.el.addEventListener('input', this.onInput)
    document.addEventListener('submit', this.onSave, true)
    document.addEventListener('brando:save', this.onSave, true)
  },

  destroyed() {
    this.el.removeEventListener('click', this.onClick)
    this.el.removeEventListener('input', this.onInput)
    document.removeEventListener('submit', this.onSave, true)
    document.removeEventListener('brando:save', this.onSave, true)
  },

  beforeUpdate(toEl) {
    this.restore = null
    if (!this.pending.size) return

    const rows = valueRows(this.el)
    const drawn = valueRows(toEl).map(serverValue)
    const shown = rows.map((row) => (this.pending.has(row) ? '' : serverValue(row)))
    const held = rows.filter((row) => !this.pending.has(row)).map(serverValue)

    if (startsWith(drawn, shown) || !startsWith(drawn, held)) return this.settle()

    let before = 0
    this.restore = []
    rows.forEach((row) => {
      if (this.pending.has(row)) {
        this.restore.push({ row, before, focused: row.contains(document.activeElement) })
        row.remove()
      } else {
        before++
      }
    })
  },

  // A row goes back before the server row it was before, and never below the
  // empty row.
  updated() {
    const restore = this.restore
    this.restore = null
    if (!restore) return

    restore.forEach(({ row, before }, index) => {
      const rows = this.rows()
      rows[Math.min(before + index, rows.length - 1)].before(row)
    })
    this.renumber()
    restore.find(({ focused }) => focused)?.row.querySelector('input').focus()
  },

  rows() {
    return [...this.el.querySelectorAll(':scope > .string-list-row')]
  },

  // No row is pending any more: every row takes its position as its id.
  settle() {
    if (!this.pending.size) return
    this.pending.clear()
    this.renumber()
  },

  // The clicked row is a value row, so its clone has the gutter and buttons
  // a value row needs; only its value goes. The clone's icons lose their
  // LiveView ids, which a patch would otherwise move into the server's rows.
  insertAt(row) {
    const added = row.cloneNode(true)
    const input = added.querySelector('input')
    input.value = ''
    input.removeAttribute('value')
    added.querySelectorAll('[data-phx-id]').forEach((el) => el.removeAttribute('data-phx-id'))
    row.before(added)
    if (!this.el.hasAttribute('data-sync-insert')) this.pending.set(added, `${this.el.id}_inserted_${++this.inserted}`)
    this.renumber()
    if (this.el.hasAttribute('data-sync-insert')) this.sendNow(input)
    input.focus()

    if (!prefersReducedMotion()) {
      added.animate(
        [
          { opacity: 0, backgroundColor: '#e8f1e5' },
          { opacity: 1, backgroundColor: '#e8f1e5', offset: 0.35 },
          { opacity: 1, backgroundColor: 'transparent' }
        ],
        { duration: 900, easing: 'ease-out' }
      )
    }
  },

  remove(row) {
    const rows = this.rows()
    const next = rows[rows.indexOf(row) + 1]
    this.pending.delete(row)
    row.remove()
    this.renumber()

    const input = next?.querySelector('input')
    if (!input) return
    // A structural change must reach the transformer immediately. Its hook
    // locks the row until this reply arrives, so an older reply cannot restore
    // removed members while a text debounce is still waiting to send them.
    input.dispatchEvent(new Event('change', { bubbles: true }))
    input.focus()
  },

  // LiveView reads `phx-debounce` while the event is dispatched, so this
  // change goes undebounced and typing in the row is debounced as before.
  sendNow(input) {
    const debounce = input.getAttribute('phx-debounce')
    input.removeAttribute('phx-debounce')
    input.dispatchEvent(new Event('change', { bubbles: true }))
    if (debounce !== null) input.setAttribute('phx-debounce', debounce)
  },

  // The number shown counts every row; the id counts the rows the server
  // draws.
  renumber() {
    const base = this.el.id
    let drawn = 0
    this.rows().forEach((row, index) => {
      const input = row.querySelector('input')
      input.id = this.pending.get(row) ?? `${base}_${drawn++}`
      input.setAttribute('aria-label', input.getAttribute('aria-label').replace(/\d+$/, index + 1))
      const number = row.querySelector('.string-list-gutter > span')
      if (number) number.textContent = index + 1
    })
  }
})
