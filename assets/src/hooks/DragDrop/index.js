export default app => ({
  mounted() {
    this.uploadTargetName = this.el.dataset.uploadTarget || null
    this.uploadFormSelector = this.el.dataset.uploadForm || null
    this.dragResetTimer = null
    this.handleDragEnter = this.highlight.bind(this)
    this.handleDragOver = this.highlight.bind(this)
    this.handleDragLeave = this.unhighlight.bind(this)
    this.handleDrop = this.handleDrop.bind(this)
    this.handleWindowDragEnd = this.clearDragState.bind(this)
    this.handleDocumentChange = this.handleDocumentChange.bind(this)

    this.el.addEventListener('dragenter', this.handleDragEnter, false)
    this.el.addEventListener('dragover', this.handleDragOver, false)
    this.el.addEventListener('dragleave', this.handleDragLeave, false)
    this.el.addEventListener('drop', this.handleDrop, false)
    window.addEventListener('dragend', this.handleWindowDragEnd, false)
    document.addEventListener('change', this.handleDocumentChange, true)
  },

  destroyed() {
    this.el.removeEventListener('dragenter', this.handleDragEnter, false)
    this.el.removeEventListener('dragover', this.handleDragOver, false)
    this.el.removeEventListener('dragleave', this.handleDragLeave, false)
    this.el.removeEventListener('drop', this.handleDrop, false)
    window.removeEventListener('dragend', this.handleWindowDragEnd, false)
    document.removeEventListener('change', this.handleDocumentChange, true)
    this.clearDragState()
  },

  highlight(e) {
    e.preventDefault()
    this.el.classList.add('dragging')
    clearTimeout(this.dragResetTimer)
  },

  unhighlight(e) {
    e.preventDefault()
    clearTimeout(this.dragResetTimer)
    this.dragResetTimer = setTimeout(() => this.clearDragState(), 120)
  },

  handleDrop(e) {
    e.preventDefault()
    const files = e.dataTransfer?.files
    this.clearDragState()

    if (!files || files.length === 0 || !this.uploadTargetName) return

    this.pushEventTo(this.el, 'picker_upload_started', {
      upload_name: this.uploadTargetName,
    })

    // If a native phx-drop-target is present, let LiveView handle the drop.
    // We only provide optimistic UI state here.
    if (this.el.hasAttribute('phx-drop-target')) return

    const formSelector = this.resolveFormSelector()
    if (!formSelector) return

    this.uploadTo(formSelector, this.uploadTargetName, files)
  },

  handleDocumentChange(e) {
    const input = e?.target

    if (!(input instanceof HTMLInputElement) || input.type !== 'file') return
    if (!this.uploadTargetName || input.name !== this.uploadTargetName) return
    if (!input.files || input.files.length === 0) return

    const formSelector = this.resolveFormSelector()
    if (!formSelector) return

    this.pushEventTo(this.el, 'picker_upload_started', {
      upload_name: this.uploadTargetName,
    })
  },

  clearDragState() {
    clearTimeout(this.dragResetTimer)
    this.dragResetTimer = null
    this.el.classList.remove('dragging')
  },

  resolveFormSelector() {
    if (this.uploadFormSelector) return this.uploadFormSelector

    const parentForm = this.el.closest('form')
    if (parentForm?.id) return `#${parentForm.id}`

    const uploadInput = this.uploadTargetName ? document.querySelector(`input[name="${this.uploadTargetName}"]`) : null
    const uploadForm = uploadInput?.closest('form')
    if (uploadForm?.id) return `#${uploadForm.id}`

    return null
  },

})
