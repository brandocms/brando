// The rows of an inline subform, a table block or a variable list: a row added with Insert or
// Add opens over 350ms, making space as its contents appear.
//
// Rows are keyed by position, so after an insert the server patches the
// existing row elements with shifted content and adds one at the end. The new
// row is the one at the clicked position, whichever element now holds it.
// The Web Animations API leaves no inline style for a patch to strip.
import revealRow from '../../rowMotion'

const ROWS = '.subform-entry, .table-row'

export default () => ({
  mounted() {
    this.pending = null
    this.count = this.rows().length

    this.onRemove = event => {
      if (event.target.closest('[phx-hook="Brando.TableRows"]') !== this.el) return
      const row = event.target.closest(this.el.dataset.rowSelector || ROWS)
      const animation = row && revealRow(row, true)
      if (!animation) { event.detail.done?.(); return }
      const button = event.target
      // The exiting row still has its inputs until the patch lands. Include
      // the same drop parameter in any Save/change serialized meanwhile, so
      // those old inputs cannot restore the row. Ordinary FormData omits the
      // clicked button itself. The temporary input goes with the next patch.
      let drop
      if (button.name) {
        drop = document.createElement('input')
        drop.type = 'hidden'
        drop.name = button.name
        drop.value = button.value
        if (button.hasAttribute('form')) drop.setAttribute('form', button.getAttribute('form'))
        row.append(drop)
      }
      this.removing = { row, animation, drop, count: this.count }
      // Push the existing change immediately; only its DOM patch waits for the
      // exit. Index-keyed rows otherwise show their neighbour's content halfway
      // through leaving. Keep the collapsed effect until that patch arrives.
      animation.finished.catch(() => {}).finally(() => event.detail.done?.())
      this.removeTimer = setTimeout(() => this.finishRemove(), 5000)
    }
    this.el.addEventListener('b:row-remove', this.onRemove)

    this.onClick = (event) => {
      if (this.removing) {
        event.preventDefault()
        event.stopPropagation()
        return
      }
      const remove = event.target.closest('.subform-delete, .identifier-remove button')
      if (remove && remove.closest('[phx-hook="Brando.TableRows"]') === this.el) {
        this.liveSocket.execJS(remove, JSON.stringify([
          ['dispatch', { event: 'b:row-remove', blocking: true }],
        ]))
        return
      }
      // Add appends and is detected by the count. A nested plain subform's
      // Add sits outside its own hook, so it must not select an outer row.
      const button = event.target.closest('.subform-insert')
      if (!button || button.closest('[phx-hook="Brando.TableRows"]') !== this.el) return

      const rows = this.rows()
      const row = button.closest('.subform-entry, .table-row')
      const index = rows.indexOf(row)
      this.pending = { index: index < 0 ? rows.length : index }
    }

    this.observer = new MutationObserver(() => this.reveal())
    this.observer.observe(this.el, { childList: true, subtree: true })
    this.el.addEventListener('click', this.onClick)
  },

  destroyed() {
    this.observer.disconnect()
    this.el.removeEventListener('click', this.onClick)
    this.el.removeEventListener('b:row-remove', this.onRemove)
    this.finishRemove(false)
  },

  finishRemove(settleHover = true) {
    clearTimeout(this.removeTimer)
    cancelAnimationFrame(this.settleFrame)
    // The row now under the pointer was already hovered during the slide.
    // An index-keyed patch reuses the exiting DOM node for it; don't restart
    // its background and tool fades from zero for that one painted handoff.
    if (this.removing && settleHover && this.el.isConnected) {
      this.el.dataset.rowsSettling = ''
      this.settleFrame = requestAnimationFrame(() => {
        this.settleFrame = requestAnimationFrame(() => delete this.el.dataset.rowsSettling)
      })
    } else {
      delete this.el.dataset.rowsSettling
    }
    this.removing?.animation.cancel()
    this.removing?.drop?.remove()
    this.removing = null
  },

  rows() {
    return [...this.el.querySelectorAll(this.el.dataset.rowSelector || ROWS)]
      .filter(row => row.parentElement.closest('[phx-hook="Brando.TableRows"]') === this.el)
  },

  reveal() {
    const rows = this.rows()
    if (this.removing && (rows.length < this.removing.count || !this.removing.row.isConnected)) this.finishRemove()
    const added = rows.length - this.count
    this.count = rows.length
    if (added <= 0) return
    const index = this.pending?.index ?? rows.length - added
    this.pending = null
    rows.slice(index, index + added).forEach(row => revealRow(row))
  }
})
