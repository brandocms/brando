/**
 * Brando.ModulePickerKeys — the module picker's search field drives the
 * results from the keyboard: ↑↓ moves between the module cards shown, Enter
 * inserts the one marked (the first when none is), Escape leaves it to the
 * modal. The mark is `.is-keyboard` on the card, reset as the results change.
 */
export default () => ({
  mounted() {
    this.index = -1

    this.el.addEventListener('keydown', e => {
      const cards = this.cards()
      if (!cards.length) return

      if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
        e.preventDefault()
        const step = e.key === 'ArrowDown' ? 1 : -1
        this.index = Math.max(0, Math.min(cards.length - 1, this.index + step))
        this.mark(cards)
      } else if (e.key === 'Enter') {
        e.preventDefault()
        cards[Math.max(this.index, 0)].click()
      }
    })

    // Typing changes the results; the mark starts over
    this.el.addEventListener('input', () => {
      this.index = -1
    })
  },

  updated() {
    this.mark(this.cards())
  },

  cards() {
    const picker = this.el.closest('.module-picker')
    return picker ? [...picker.querySelectorAll('.module-picker-results .module-card')] : []
  },

  mark(cards) {
    cards.forEach((card, i) => card.classList.toggle('is-keyboard', i === this.index))
    const marked = cards[this.index]
    if (marked) marked.scrollIntoView({ block: 'nearest' })
  },
})
