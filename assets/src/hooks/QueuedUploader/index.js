export default (app) => ({
  /**
   * Initializes file upload handling with concurrent upload support
   * Gets configuration from element's data attributes and sets up event listeners
   */
  async mounted() {
    this.uploadQueue = []
    this.activeUploads = 0
    this.batchActive = false
    this.batchTotal = 0
    this.batchCompleted = 0
    this.currentFileProgress = 0
    this.dropListenersAttached = false
    this.documentChangeAttached = false
    this.dragDepth = 0
    this.dragResetTimer = null
    this.refreshConfig()

    this.handleChange = (event) => {
      if (!(event.target instanceof HTMLInputElement) || event.target.type !== 'file') return
      if (event.target.name && !this.uploadNameMatches(event.target.name)) return

      event.preventDefault()
      this.enqueueFiles(event.target.files)
      event.target.value = ''
    }

    this.nextFileHandler = ({ upload_target } = {}) => {
      if (upload_target && !this.uploadNameMatches(upload_target)) return
      this.activeUploads = Math.max(0, this.activeUploads - 1)
      this.markFileComplete()
      this.flushQueue()
      this.finishBatchIfComplete()
    }

    this.handleDragEnter = this.handleDragEnter.bind(this)
    this.handleDragOver = this.handleDragOver.bind(this)
    this.handleDragLeave = this.unhighlight.bind(this)
    this.handleDrop = this.handleDrop.bind(this)
    this.handleWindowDragEnd = this.clearDragState.bind(this)
    this.handlePickerProgress = this.handlePickerProgress.bind(this)
    this.handleDocumentChange = this.handleDocumentChange.bind(this)

    this.el.addEventListener('change', this.handleChange)
    this.handleEvent('upload_send_next_file', this.nextFileHandler)
    this.syncDropListeners()
    this.syncDocumentChangeListener()
    this.attachPickerProgressListener()
    this.syncPickerProgressUI()
  },

  updated() {
    this.refreshConfig()
    this.syncDropListeners()
    this.syncDocumentChangeListener()
    this.attachPickerProgressListener()
    this.syncPickerProgressUI()
  },

  destroyed() {
    if (this.handleChange) {
      this.el.removeEventListener('change', this.handleChange)
    }

    this.detachDropListeners()
    this.detachDocumentChangeListener()
    this.detachPickerProgressListener()
    this.clearDragState()
  },

  refreshConfig() {
    const previousTarget = this.uploadTargetName

    this.maxConcurrentUploads = parseInt(this.el.dataset.maxConcurrency, 10) || 1
    this.uploadTargetName = this.el.dataset.uploadTarget || ''
    this.uploadFormSelector = this.el.dataset.uploadForm || null
    this.progressTarget = this.el.dataset.progressTarget || null
    this.controlsProgress = this.el.dataset.progressListener === 'true'
    this.listenDocumentChange = this.el.dataset.listenDocumentChange === 'true'
    this.dropEnabled = this.el.dataset.enableDrop === 'true' && !!this.uploadTargetName

    if (previousTarget && previousTarget !== this.uploadTargetName) {
      this.uploadQueue = []
      this.activeUploads = 0
      this.currentFileProgress = 0
      this.resetBatchState()
    }
  },

  attachPickerProgressListener() {
    if (!this.controlsProgress) return
    if (!app.userChannel || this.pickerProgressRef) return

    this.pickerProgressRef = app.userChannel.on('picker:upload_progress', this.handlePickerProgress)
  },

  detachPickerProgressListener() {
    if (!app.userChannel || !this.pickerProgressRef) return

    app.userChannel.off('picker:upload_progress', this.pickerProgressRef)
    this.pickerProgressRef = null
  },

  handlePickerProgress({ upload_name, progress } = _payload) {
    if (!this.controlsProgress) return
    if (!this.uploadNameMatches(upload_name)) return

    this.currentFileProgress = this.normalizeProgress(progress)
    this.syncPickerProgressUI()
  },

  syncDropListeners() {
    if (this.dropEnabled && !this.dropListenersAttached) {
      this.el.addEventListener('dragenter', this.handleDragEnter, false)
      this.el.addEventListener('dragover', this.handleDragOver, false)
      this.el.addEventListener('dragleave', this.handleDragLeave, false)
      this.el.addEventListener('drop', this.handleDrop, false)
      window.addEventListener('dragend', this.handleWindowDragEnd, false)
      this.dropListenersAttached = true
    } else if (!this.dropEnabled && this.dropListenersAttached) {
      this.detachDropListeners()
      this.clearDragState()
    }
  },

  syncDocumentChangeListener() {
    if (this.listenDocumentChange && !this.documentChangeAttached) {
      document.addEventListener('change', this.handleDocumentChange, true)
      this.documentChangeAttached = true
    } else if (!this.listenDocumentChange && this.documentChangeAttached) {
      this.detachDocumentChangeListener()
    }
  },

  detachDocumentChangeListener() {
    if (!this.documentChangeAttached) return

    document.removeEventListener('change', this.handleDocumentChange, true)
    this.documentChangeAttached = false
  },

  handleDocumentChange(event) {
    if (!this.listenDocumentChange || !this.uploadTargetName) return

    const input = event?.target
    if (!(input instanceof HTMLInputElement) || input.type !== 'file') return
    if (this.el.contains(input)) return
    if (!this.uploadNameMatches(input.name)) return
    if (!input.files || input.files.length === 0) return

    event.preventDefault()
    this.enqueueFiles(input.files)
    input.value = ''
  },

  detachDropListeners() {
    if (!this.dropListenersAttached) return

    this.el.removeEventListener('dragenter', this.handleDragEnter, false)
    this.el.removeEventListener('dragover', this.handleDragOver, false)
    this.el.removeEventListener('dragleave', this.handleDragLeave, false)
    this.el.removeEventListener('drop', this.handleDrop, false)
    window.removeEventListener('dragend', this.handleWindowDragEnd, false)
    this.dropListenersAttached = false
  },

  notifyUploadStarted() {
    if (!this.progressTarget || !this.uploadTargetName) return

    this.currentFileProgress = 0
    this.syncPickerProgressUI()

    this.pushEventTo(this.progressTarget, 'picker_upload_started', {
      upload_name: this.uploadTargetName,
      total_files: this.batchTotal,
      completed_files: this.batchCompleted,
    })
  },

  notifyFileComplete() {
    if (!this.progressTarget || !this.uploadTargetName) return

    this.pushEventTo(this.progressTarget, 'picker_upload_file_complete', {
      upload_name: this.uploadTargetName,
      total_files: this.batchTotal,
      completed_files: this.batchCompleted,
    })
  },

  notifyUploadFinished() {
    if (!this.progressTarget || !this.uploadTargetName) return

    this.pushEventTo(this.progressTarget, 'picker_upload_finished', {
      upload_name: this.uploadTargetName,
      total_files: this.batchTotal,
      completed_files: this.batchCompleted,
    })
  },

  eventHasFiles(e) {
    const dataTransfer = e?.dataTransfer
    if (!dataTransfer) return false
    if (dataTransfer.files && dataTransfer.files.length > 0) return true
    return Array.from(dataTransfer.types || []).includes('Files')
  },

  enqueueFiles(fileList) {
    if (!this.uploadTargetName || !fileList || fileList.length === 0) return

    const files = Array.from(fileList)
    if (files.length === 0) return

    const startingFresh = this.uploadQueue.length === 0 && this.activeUploads === 0
    if (startingFresh || !this.batchActive) {
      this.batchActive = true
      this.batchTotal = files.length
      this.batchCompleted = 0
    } else {
      this.batchTotal += files.length
    }

    this.uploadQueue.push(...files)

    this.notifyUploadStarted()

    this.flushQueue()
  },

  flushQueue() {
    if (!this.uploadTargetName) return

    const availableSlots = this.maxConcurrentUploads - this.activeUploads
    if (availableSlots <= 0 || this.uploadQueue.length === 0) return

    const nextBatch = this.uploadQueue.splice(0, availableSlots)
    if (nextBatch.length === 0) return

    this.activeUploads += nextBatch.length
    this.currentFileProgress = 0
    this.syncPickerProgressUI()

    window.requestAnimationFrame(() => {
      this.forwardUpload(nextBatch)
    })
  },

  forwardUpload(files) {
    const formSelector = this.resolveFormSelector()

    if (formSelector) {
      this.uploadTo(formSelector, this.uploadTargetName, files)
      return
    }

    this.upload(this.uploadTargetName, files)
  },

  resolveFormSelector() {
    if (this.uploadFormSelector) return this.uploadFormSelector

    const parentForm = this.el.closest('form')
    if (parentForm?.id) return `#${parentForm.id}`

    const uploadInput = document.querySelector(`input[name="${this.uploadTargetName}"]`)
    const uploadForm = uploadInput?.closest('form')
    if (uploadForm?.id) return `#${uploadForm.id}`

    return null
  },

  handleDragEnter(e) {
    if (!this.dropEnabled || !this.eventHasFiles(e)) return

    e.preventDefault()
    e.stopPropagation()
    this.dragDepth += 1
    clearTimeout(this.dragResetTimer)
    this.el.classList.add('dragging')
  },

  handleDragOver(e) {
    if (!this.dropEnabled || !this.eventHasFiles(e)) return

    e.preventDefault()
    e.stopPropagation()
    clearTimeout(this.dragResetTimer)
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'copy'
    this.el.classList.add('dragging')
  },

  unhighlight(e) {
    if (!this.dropEnabled) return

    e.preventDefault()
    e.stopPropagation()

    this.dragDepth = Math.max(0, this.dragDepth - 1)
    if (this.dragDepth > 0) return

    clearTimeout(this.dragResetTimer)
    this.dragResetTimer = setTimeout(() => this.clearDragState(), 60)
  },

  handleDrop(e) {
    if (!this.dropEnabled || !this.eventHasFiles(e)) return

    e.preventDefault()
    e.stopPropagation()
    this.dragDepth = 0
    this.clearDragState()
    this.enqueueFiles(e.dataTransfer?.files)
  },

  clearDragState() {
    this.dragDepth = 0
    clearTimeout(this.dragResetTimer)
    this.dragResetTimer = null
    this.el.classList.remove('dragging')
  },

  markFileComplete() {
    if (!this.batchActive) return

    this.batchCompleted = Math.min(this.batchCompleted + 1, this.batchTotal)
    this.currentFileProgress = 100
    this.syncPickerProgressUI()
    this.notifyFileComplete()
  },

  finishBatchIfComplete() {
    if (!this.batchActive) return

    if (this.uploadQueue.length === 0 && this.activeUploads === 0 && this.batchCompleted >= this.batchTotal && this.batchTotal > 0) {
      this.notifyUploadFinished()
      this.resetBatchState()
    }
  },

  resetBatchState() {
    this.batchActive = false
    this.batchTotal = 0
    this.batchCompleted = 0
  },

  normalizeProgress(progress) {
    const parsed = Number.parseInt(progress, 10)
    if (Number.isNaN(parsed)) return 0
    if (parsed < 0) return 0
    if (parsed > 100) return 100
    return parsed
  },

  normalizeUploadName(name) {
    if (name === null || name === undefined) return ''

    let normalized = String(name).trim()

    try {
      normalized = decodeURIComponent(normalized)
    } catch (_error) {
      // Keep original value when name is not URI encoded.
    }

    if (normalized.startsWith(':')) normalized = normalized.slice(1)
    if (normalized.startsWith('Elixir.')) normalized = normalized.slice(7)
    if (normalized.endsWith('[]')) normalized = normalized.slice(0, -2)

    return normalized
  },

  uploadNameMatches(name) {
    const target = this.normalizeUploadName(this.uploadTargetName)
    const incoming = this.normalizeUploadName(name)

    if (!target || !incoming) return false
    if (target === incoming) return true

    return (
      incoming.endsWith(`|${target}`) ||
      target.endsWith(`|${incoming}`) ||
      incoming.endsWith(`.${target}`) ||
      target.endsWith(`.${incoming}`)
    )
  },

  resolveProgressContainer() {
    if (this.progressTarget) {
      const target = document.querySelector(this.progressTarget)
      if (target) return target
    }

    return this.el
  },

  syncPickerProgressUI() {
    if (!this.controlsProgress) return

    const container = this.resolveProgressContainer()
    if (!container) return

    const progressWrapper = container.querySelector('.picker-upload-progress')
    if (!progressWrapper) return

    const currentLabel = progressWrapper.querySelector('.picker-upload-current')
    const progressBar = progressWrapper.querySelector('progress')
    const progress = this.normalizeProgress(this.currentFileProgress)
    const currentPrefix = progressWrapper.dataset.labelCurrentFile || 'Current file'

    if (currentLabel) {
      currentLabel.textContent = `${currentPrefix} ${progress}%`
    }

    if (progressBar) {
      progressBar.value = progress
      progressBar.textContent = `${progress}%`
    }
  },
})
