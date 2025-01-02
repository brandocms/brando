export default (app) => ({
  /**
   * Initializes file upload handling with concurrent upload support
   * Gets configuration from element's data attributes and sets up event listeners
   */
  async mounted() {
    const maxConcurrentUploads = parseInt(this.el.dataset.maxConcurrency) || 1
    const uploadTargetName = this.el.dataset.uploadTarget || 'transformer'
    let uploadQueue = []

    this.el.addEventListener('input', async (event) => {
      event.preventDefault()

      if (event.target instanceof HTMLInputElement) {
        const selectedFiles = event.target.files
        if (selectedFiles) {
          uploadQueue = Array.from(selectedFiles)
          const initialBatch = uploadQueue.slice(0, maxConcurrentUploads)
          window.requestAnimationFrame(() => {
            this.upload(uploadTargetName, initialBatch)
          })
          uploadQueue.splice(0, maxConcurrentUploads)
        }
      }
    })

    this.handleEvent('upload_send_next_file', () => {
      if (uploadQueue.length > 0) {
        const nextFile = uploadQueue.shift()
        if (nextFile != undefined) {
          window.requestAnimationFrame(() => {
            this.upload(uploadTargetName, [nextFile])
          })
        }
      }
    })
  },
})
