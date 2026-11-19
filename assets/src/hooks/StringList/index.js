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
// Ids are renumbered after each change so they stay positional: when the
// server's render arrives, every row is patched in place and the focused one
// keeps its focus.
export default () => ({
  mounted() {
    this.onClick = (event) => {
      const insert = event.target.closest('.string-list-insert')
      const remove = event.target.closest('.string-list-remove')
      if (insert) this.insertAt(insert.closest('.string-list-row'))
      if (remove) this.remove(remove.closest('.string-list-row'))
    }

    this.el.addEventListener('click', this.onClick)
  },

  destroyed() {
    this.el.removeEventListener('click', this.onClick)
  },

  rows() {
    return [...this.el.querySelectorAll(':scope > .string-list-row')]
  },

  // The clicked row is a value row, so its clone has the gutter and buttons
  // a value row needs; only its value goes.
  insertAt(row) {
    const added = row.cloneNode(true)
    const input = added.querySelector('input')
    input.value = ''
    input.removeAttribute('value')
    row.before(added)
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

  renumber() {
    const base = this.el.id
    this.rows().forEach((row, index) => {
      const input = row.querySelector('input')
      input.id = `${base}_${index}`
      input.setAttribute('aria-label', input.getAttribute('aria-label').replace(/\d+$/, index + 1))
      const number = row.querySelector('.string-list-gutter > span')
      if (number) number.textContent = index + 1
    })
  }
})
