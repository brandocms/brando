import { Dom } from '@brandocms/jupiter'

// Saving a form that owns blocks or transformers takes two submits: the first
// asks every BlockField/Transformer to ship its state, and once they answer the
// server pushes `b:submit` so we re-submit with the collected data.
//
// LiveView silently discards a submit while the form is still marked as
// submitting — `View.pushFormSubmit` guards its push with
// `!(formEl.hasAttribute("data-phx-ref-src") && formEl.classList.contains("phx-submit-loading"))`
// and has no else branch. `b:submit` rides along on the reply to the first
// submit, so it can arrive before LiveView has released those refs. When that
// happens the second submit evaporates: the server never receives "save", never
// clears `:processing`, and the button stays disabled on "Processing. Please
// wait..." until the page is reloaded.
//
// Wait for the form to be released before re-dispatching. `setTimeout` rather
// than `requestAnimationFrame` so a backgrounded tab still finishes its save.
const RELEASE_POLL_MS = 16
const RELEASE_TIMEOUT_MS = 2000

export default app => ({
  mounted() {
    this.$formWrapper = Dom.find(`#${this.el.dataset.formId}-el`)
    this.$form = Dom.find(this.$formWrapper, 'form.main-form')

    this.el.addEventListener('click', e => {
      e.preventDefault()
      this.submitForm()
    })

    this.handleEvent('b:submit', () => this.submitWhenReleased(Date.now()))
  },

  destroyed() {
    if (this._releaseTimer) {
      clearTimeout(this._releaseTimer)
      this._releaseTimer = null
    }
  },

  // Mirrors the condition LiveView itself checks before pushing.
  isSubmitting() {
    return (
      this.$form.hasAttribute('data-phx-ref-src') &&
      this.$form.classList.contains('phx-submit-loading')
    )
  },

  submitWhenReleased(startedAt) {
    if (this.isSubmitting() && Date.now() - startedAt < RELEASE_TIMEOUT_MS) {
      this._releaseTimer = setTimeout(() => this.submitWhenReleased(startedAt), RELEASE_POLL_MS)
      return
    }

    // Past the deadline we submit anyway: a dropped submit leaves the form
    // locked, so a best-effort attempt beats giving up silently.
    this._releaseTimer = null
    this.submitForm()
  },

  submitForm() {
    this.$form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
  }
})
