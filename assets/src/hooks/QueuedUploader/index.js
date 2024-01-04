export default app => ({
  async mounted() {
    const chunkSize = 5
    let filesRemaining = []
    console.log('mounted queue hook')
    this.el.addEventListener('input', async event => {
      console.log('got input!', event.target, event.currentTarget)
      event.preventDefault()

      if (event.target instanceof HTMLInputElement) {
        const files_html = event.target.files
        console.log('in instanceof', files_html)
        if (files_html) {
          const files = Array.from(files_html)
          filesRemaining = files
          const firstFiles = files.slice(0, chunkSize)
          console.log('uploading', firstFiles)
          this.upload('transformer', firstFiles)

          filesRemaining.splice(0, chunkSize)
        }
      }
    })

    this.handleEvent('uploader_next_chunk', () => {
      console.log('Uploading more files! Remainder:', filesRemaining)
      const files = filesRemaining.slice(0, chunkSize)
      if (files.length > 0) {
        this.upload('transformer', files)
        filesRemaining.splice(0, chunkSize)
      } else {
        console.log('Done uploading, noop!')
      }
    })
  }
})
