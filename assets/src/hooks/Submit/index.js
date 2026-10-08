import { Dom } from '@brandocms/jupiter'
import saveForm from '../Form/saveForm'

// Saving a form that owns blocks or transformers takes two saves: the first
// asks every BlockField/Transformer to ship its state, and once they answer the
// server pushes `b:submit` so we save again with the collected data. Neither is
// a form submit (`../Form/saveForm.js`).
//
// A native submit (Enter in a field) still goes through LiveView, which
// silently discards a submit while the form is marked as submitting —
// `View.pushFormSubmit` guards its push with
// `!(formEl.hasAttribute("data-phx-ref-src") && formEl.classList.contains("phx-submit-loading"))`.
// `b:submit` can answer such a submit before LiveView has released those refs,
// so the second save waits for the form to be released.
// `setTimeout` rather than `requestAnimationFrame` so a backgrounded tab still
// finishes its save.
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

    // The write carries the token of the `b:submit` it answers: one that
    // arrives after its save already wrote is ignored by the server.
    this.handleEvent('b:submit', ({ token } = {}) => this.submitWhenReleased(Date.now(), token))
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

  submitWhenReleased(startedAt, token) {
    if (this.isSubmitting() && Date.now() - startedAt < RELEASE_TIMEOUT_MS) {
      this._releaseTimer = setTimeout(() => this.submitWhenReleased(startedAt, token), RELEASE_POLL_MS)
      return
    }

    // Past the deadline we submit anyway: a dropped submit leaves the form
    // locked, so a best-effort attempt beats giving up silently.
    this._releaseTimer = null
    this.submitForm(token)
  },

  // Not a form submit: see `../Form/saveForm.js`.
  submitForm(token) {
    saveForm(this, this.$form, { token })
  }
})
