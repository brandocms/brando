export default (app) => ({
  mounted() {
    const input = this.el.querySelector('input[type="file"]')
    const uploadName = this.el.dataset.uploadName
    const mode = this.el.dataset.uploadMode || 'single'
    this._uploadQueue = []
    this._pendingProcessing = 0
    this._progressState = { visible: false, phase: 'idle', progress: 0 }

    // Listen for progress and completion via PubSub → user channel.
    // This bypasses the LV diff pipeline so updates arrive in real-time.
    if (app.userChannel) {
      this._progressRef = app.userChannel.on('block:upload_progress', ({ upload_name, progress }) => {
        if (upload_name === uploadName) {
          this.showProgress(progress)
        }
      })

      this._completeRef = app.userChannel.on('block:upload_complete', ({ upload_name }) => {
        if (upload_name === uploadName) {
          this._pendingProcessing += 1
          this.showProcessing()
        }
      })

      this._processedRef = app.userChannel.on('block:upload_processed', ({ upload_name }) => {
        if (upload_name !== uploadName) return
        this._pendingProcessing = Math.max(0, this._pendingProcessing - 1)
        this.maybeHideProgress()
      })

      // Server signals "send next file" after consuming the previous one.
      // Only relevant in multi mode (gallery uploads).
      this._nextFileRef = app.userChannel.on('block:upload_next_file', ({ upload_name }) => {
        console.log('[BlockUpload] received block:upload_next_file', upload_name, 'queue length:', this._uploadQueue.length)
        if (upload_name !== uploadName) return

        if (this._uploadQueue.length > 0) {
          const nextFile = this._uploadQueue.shift()
          console.log('[BlockUpload] uploading next file:', nextFile.name)
          // Delay to let the LV diff (which clears the consumed entry from
          // the upload state) arrive at the client before we push a new file.
          // Without this, the client-side upload state still shows max_entries
          // reached and silently rejects the new upload.
          setTimeout(() => {
            this.forwardUpload(uploadName, [nextFile])
          }, 100)
        } else {
          console.log('[BlockUpload] queue empty, waiting for processing to complete')
          this.maybeHideProgress()
        }
      })
    }

    if (input) {
      input.addEventListener('change', (e) => {
        e.stopPropagation()
        const files = e.target.files
        if (files && files.length > 0) {
          if (mode === 'multi' && files.length > 1) {
            // Queue all files after the first, send first immediately
            this._uploadQueue = Array.from(files).slice(1)
            console.log('[BlockUpload] multi: queued', this._uploadQueue.length, 'files, uploading first:', files[0].name)
            this.forwardUpload(uploadName, [files[0]])
          } else {
            this.forwardUpload(uploadName, files)
          }
        }
        input.value = ''
      })
    }

    // Click handling: mode-dependent
    if (mode === 'single') {
      // Existing: click anywhere (except buttons) opens file dialog
      this.el.addEventListener('click', (e) => {
        if (e.target.closest('button') || e.target.closest('a')) return
        e.stopPropagation()
        if (input) input.click()
      })
    } else {
      // Multi: only .upload-trigger buttons and .upload-canvas.empty clicks open dialog
      this.el.addEventListener('click', (e) => {
        if (e.target.closest('.upload-trigger') || e.target.closest('.upload-canvas.empty')) {
          e.stopPropagation()
          if (input) input.click()
        }
      })
    }

    this.el.addEventListener('dragenter', (e) => {
      e.preventDefault()
      e.stopPropagation()
    })

    this.el.addEventListener('dragover', (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.add('dragging')
    })

    this.el.addEventListener('dragleave', (e) => {
      e.stopPropagation()
      this.el.classList.remove('dragging')
    })

    this.el.addEventListener('drop', (e) => {
      e.preventDefault()
      e.stopPropagation()
      this.el.classList.remove('dragging')
      const files = e.dataTransfer.files
      if (files && files.length > 0) {
        if (mode === 'multi' && files.length > 1) {
          this._uploadQueue = Array.from(files).slice(1)
          this.forwardUpload(uploadName, [files[0]])
        } else {
          this.forwardUpload(uploadName, files)
        }
      }
    })

    this.syncProgressUI()
  },

  updated() {
    // LiveView diffs can patch this subtree while uploads progress.
    // Re-apply local UI state to avoid progress bar flicker/reset.
    this.syncProgressUI()
  },

  destroyed() {
    if (app.userChannel) {
      if (this._progressRef) app.userChannel.off('block:upload_progress', this._progressRef)
      if (this._completeRef) app.userChannel.off('block:upload_complete', this._completeRef)
      if (this._processedRef) app.userChannel.off('block:upload_processed', this._processedRef)
      if (this._nextFileRef) app.userChannel.off('block:upload_next_file', this._nextFileRef)
    }
  },

  showProgress(progress) {
    this._progressState = {
      visible: true,
      phase: 'uploading',
      progress,
    }
    this.syncProgressUI()
  },

  showProcessing() {
    this._progressState = {
      ...this._progressState,
      visible: true,
      phase: 'processing',
    }
    this.syncProgressUI()
  },

  maybeHideProgress() {
    if (this._uploadQueue.length === 0 && this._pendingProcessing === 0) {
      this.hideProgress()
    } else {
      this.showProcessing()
    }
  },

  hideProgress() {
    this._progressState = { visible: false, phase: 'idle', progress: 0 }
    this.syncProgressUI()
  },

  syncProgressUI() {
    const progressEl = this.el.querySelector('.upload-progress')
    const figure = this.el.querySelector('figure')
    const instructions = this.el.querySelector('.instructions')

    if (!progressEl) return

    if (!this._progressState.visible) {
      progressEl.style.display = 'none'
      if (figure) figure.style.display = ''
      if (instructions) instructions.style.display = ''
      return
    }

    progressEl.style.display = ''
    if (figure) figure.style.display = 'none'
    if (instructions) instructions.style.display = 'none'

    const bar = progressEl.querySelector('progress')
    const label = progressEl.querySelector('.upload-progress-label')

    if (this._progressState.phase === 'uploading') {
      const progress = this._progressState.progress || 0
      if (bar) {
        bar.value = progress
        bar.textContent = `${progress}%`
      }
      if (label) {
        const uploadingLabel = this.el.dataset.labelUploading || 'Uploading'
        label.textContent = `${uploadingLabel} ${progress}%`
      }
    } else if (this._progressState.phase === 'processing') {
      if (bar) bar.removeAttribute('value') // indeterminate state
      if (label) label.textContent = this.el.dataset.labelProcessing || 'Processing image sizes...'
    }
  },

  forwardUpload(uploadName, files) {
    const liveInput = document.querySelector(`input[name="${uploadName}"]`)
    if (!liveInput) {
      console.error(`BlockUpload: no live_file_input found for "${uploadName}"`)
      return
    }

    const formEl = liveInput.closest('form')
    if (!formEl || !formEl.id) {
      console.error(`BlockUpload: no parent form found for "${uploadName}"`)
      return
    }

    this.uploadTo(`#${formEl.id}`, uploadName, files)
  },
})
