/**
 * Brando.AssistantComposer — the assistant's message field.
 *
 * Enter sends the message, Shift+Enter adds a line; an IME composition is
 * never interrupted. After sending, the server pushes `b:assistant:clear`;
 * a suggestion pushes `b:assistant:fill` with its text.
 */
export default () => ({
  mounted() {
    this.el.addEventListener('keydown', e => {
      if (e.key !== 'Enter' || e.shiftKey || e.isComposing) return
      e.preventDefault()
      if (this.el.value.trim() !== '') this.el.form.requestSubmit()
    })

    this.handleEvent('b:assistant:fill', ({ text }) => {
      this.el.value = text
      this.el.focus()
      this.el.setSelectionRange(text.length, text.length)
    })

    // Opening a page preview brings the review column's top into view.
    this.handleEvent('b:assistant:review_top', () => {
      const review = document.querySelector('.assistant-review')
      if (review && review.getBoundingClientRect().top < 0) review.scrollIntoView({ block: 'start' })
    })

    this.handleEvent('b:assistant:clear', () => {
      this.el.value = ''
      this.el.focus()
    })
  },
})
