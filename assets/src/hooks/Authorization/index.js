export default () => ({
  mounted() {
    this.beforeUnload = (event) => {
      if (this.navigationConfirmed || (!this.localEdit && this.el.dataset.dirty !== 'true')) return
      event.preventDefault()
      event.returnValue = ''
    }
    this.beforeNavigate = (event) => {
      const link = event.target.closest('a[href]')
      if (!link || link.target === '_blank' || link.hasAttribute('download') ||
          link.getAttribute('href').startsWith('#') || (!this.localEdit && this.el.dataset.dirty !== 'true')) return
      if (!window.confirm('Discard your unsaved group changes?')) {
        event.preventDefault()
        event.stopImmediatePropagation()
      } else {
        this.navigationConfirmed = true
      }
    }
    this.trackInput = (event) => {
      if (event.target.matches('[name^="group["], [name^="permissions["]')) this.localEdit = true
    }
    this.el.addEventListener('input', this.trackInput)
    window.addEventListener('beforeunload', this.beforeUnload)
    document.addEventListener('click', this.beforeNavigate, true)
    this.focusStep()
  },
  updated() { this.localEdit = false; this.navigationConfirmed = false; this.focusStep() },
  focusStep() {
    const target = this.el.querySelector('[data-access-focus]')
    if (target && target !== this.focusedStep) {
      target.focus({ preventScroll: true })
      target.scrollIntoView({ block: 'nearest' })
    }
    if (!target && this.focusedStep?.dataset.accessReturn) {
      this.el.querySelector(this.focusedStep.dataset.accessReturn)?.focus({ preventScroll: true })
    }
    this.focusedStep = target
  },
  destroyed() {
    this.el.removeEventListener('input', this.trackInput)
    window.removeEventListener('beforeunload', this.beforeUnload)
    document.removeEventListener('click', this.beforeNavigate, true)
  },
})
