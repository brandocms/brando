export default (app) => ({
  async mounted() {
    let uploadChunkSize = this.el.dataset.chunkSize || 5
    // ensure the uploadChunkSize is a number
    uploadChunkSize = parseInt(uploadChunkSize, 10)

    console.log('uploadChunkSize --', uploadChunkSize)
    const uploadFieldName = this.el.dataset.uploadField || 'transformer'
    console.log('uploadFieldName --', uploadFieldName)
    let filesRemaining = []
    this.el.addEventListener('input', async (event) => {
      event.preventDefault()
      console.log('Got input')

      if (event.target instanceof HTMLInputElement) {
        const selectedFiles = event.target.files
        if (selectedFiles) {
          const files = Array.from(selectedFiles)
          filesRemaining = files
          const currentChunk = files.slice(0, uploadChunkSize)
          console.log('this.upload', uploadFieldName, currentChunk)
          this.upload(uploadFieldName, currentChunk)
          filesRemaining.splice(0, uploadChunkSize)
        }
      }
    })

    console.log('handleEvent uploader_next_chunk')
    this.handleEvent('uploader_next_chunk', () => {
      console.log('Uploading more files! Remainder:', filesRemaining)
      const currentChunk = filesRemaining.slice(0, uploadChunkSize)
      console.log('currentChunk (event)', currentChunk)
      if (currentChunk.length > 0) {
        this.upload(uploadFieldName, currentChunk)
        filesRemaining.splice(0, uploadChunkSize)
      } else {
        console.log('Done uploading, noop!')
      }
    })
  },
})
