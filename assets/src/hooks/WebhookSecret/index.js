/**
 * Shows a webhook's new secret, once.
 *
 * The secret arrives as the `brando:webhook-secret` push event and goes
 * straight into the read-only field: it is never part of the LiveView's
 * assigns or rendered HTML, so it is gone from the page when the panel is
 * closed or the page left. The element is `phx-update="ignore"`; its
 * `hidden` attribute is ours.
 */
export default () => ({
  mounted() {
    this.input = this.el.querySelector('[data-webhook-secret-value]')
    this.copyButton = this.el.querySelector('[data-webhook-secret-copy]')

    this.handleEvent('brando:webhook-secret', ({ secret }) => {
      this.input.value = secret
      this.el.hidden = false
      // After the patch that brought the page here has settled
      requestAnimationFrame(() => {
        this.el.scrollIntoView({ block: 'center' })
        this.input.focus({ preventScroll: true })
        this.input.select()
      })
    })

    this.copyButton?.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(this.input.value)
        this.copyButton.textContent = this.copyButton.dataset.copied
      } catch {
        this.input.select()
      }
    })

    this.el.querySelector('[data-webhook-secret-done]')?.addEventListener('click', () => this.clear())
  },

  destroyed() {
    if (this.input) this.input.value = ''
  },

  clear() {
    this.input.value = ''
    this.el.hidden = true
    if (this.copyButton) this.copyButton.textContent = this.copyButton.dataset.copy
  },
})
