export default (app) => ({
  mounted() {
    const input = this.el.querySelector('input[type="file"]')
    const uploadName = this.el.dataset.uploadName

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
          this.showProcessing()
        }
      })
    }

    if (input) {
      input.addEventListener('change', (e) => {
        e.stopPropagation()
        const files = e.target.files
        if (files && files.length > 0) {
          this.forwardUpload(uploadName, files)
        }
        input.value = ''
      })
    }

    this.el.addEventListener('click', (e) => {
      if (e.target.closest('button') || e.target.closest('a')) return
      e.stopPropagation()
      if (input) input.click()
    })

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
        this.forwardUpload(uploadName, files)
      }
    })
  },

  destroyed() {
    if (app.userChannel) {
      if (this._progressRef) app.userChannel.off('block:upload_progress', this._progressRef)
      if (this._completeRef) app.userChannel.off('block:upload_complete', this._completeRef)
    }
  },

  showProgress(progress) {
    const progressEl = this.el.querySelector('.upload-progress')
    const figure = this.el.querySelector('figure')
    const instructions = this.el.querySelector('.instructions')

    if (progressEl) {
      progressEl.style.display = ''
      const bar = progressEl.querySelector('progress')
      const label = progressEl.querySelector('.upload-progress-label')
      if (bar) {
        bar.value = progress
        bar.textContent = `${progress}%`
      }
      if (label) {
        const uploadingLabel = this.el.dataset.labelUploading || 'Uploading'
        label.textContent = `${uploadingLabel} ${progress}%`
      }
    }

    if (figure) figure.style.display = 'none'
    if (instructions) instructions.style.display = 'none'
  },

  showProcessing() {
    const progressEl = this.el.querySelector('.upload-progress')
    if (progressEl) {
      const bar = progressEl.querySelector('progress')
      const label = progressEl.querySelector('.upload-progress-label')
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
