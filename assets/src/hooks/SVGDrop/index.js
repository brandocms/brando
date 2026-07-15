export default app => ({
  mounted() {
    this.target = this.el.dataset.target
    this.bindDrop()
  },

  bindDrop() {
    this.el.addEventListener('dragenter', event => {
      event.preventDefault()
      this.el.classList.add('dragging')
    })
    this.el.addEventListener('dragover', event => {
      // preventDefault marks the element as a valid drop target — without it
      // the browser never fires `drop` (it opens the file instead)
      event.preventDefault()
      this.el.classList.add('dragging')
    })
    this.el.addEventListener('dragleave', () => {
      this.el.classList.remove('dragging')
    })

    this.el.addEventListener('drop', event => {
      event.preventDefault()
      this.el.classList.remove('dragging')

      const files = event.dataTransfer.files
      if (!files.length) {
        return
      }

      const f = files.item(0)
      if (!f.name.toLowerCase().endsWith('.svg') && f.type !== 'image/svg+xml') {
        console.warn('SVGDrop: ignoring non-SVG file', f.name)
        return
      }

      this.upload(f)
    })
  },

  upload(f) {
    const reader = new FileReader()
    reader.onload = event => {
      this.pushEventTo(this.target, 'drop_svg', { code: event.target.result })
    }
    reader.readAsText(f)
  },
})
