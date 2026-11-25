/**
 * Copies the text of the read-only field `[data-copy-source]` when
 * `[data-copy-button]` is pressed, and says so on the button until the next
 * patch. Where the clipboard is refused, the text is selected to copy by hand.
 */
export default () => ({
  mounted() {
    this.el.addEventListener('click', async (event) => {
      const button = event.target.closest('[data-copy-button]')
      const source = this.el.querySelector('[data-copy-source]')
      if (!button || !source) return

      try {
        await navigator.clipboard.writeText(source.value)
        if (button.dataset.copied) button.textContent = button.dataset.copied
      } catch {
        source.select()
      }
    })
  },
})
