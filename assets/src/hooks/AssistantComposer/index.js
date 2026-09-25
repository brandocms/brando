/**
 * Brando.AssistantComposer — the assistant's message field.
 *
 * Enter sends the message, Shift+Enter adds a line; an IME composition is
 * never interrupted. After sending, the server pushes `b:assistant:clear`.
 */
export default () => ({
  mounted() {
    this.el.addEventListener('keydown', e => {
      if (e.key !== 'Enter' || e.shiftKey || e.isComposing) return
      e.preventDefault()
      if (this.el.value.trim() !== '') this.el.form.requestSubmit()
    })

    this.handleEvent('b:assistant:clear', () => {
      this.el.value = ''
      this.el.focus()
    })
  },
})
