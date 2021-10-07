import { Dom } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.target = this.el.dataset.target
    this.bindDrop()
  },

  bindDrop() {
    this.el.addEventListener('dragenter', () => { this.el.classList.add('dragging') })
    this.el.addEventListener('dragover', () => { this.el.classList.add('dragging') })
    this.el.addEventListener('dragleave', () => { this.el.classList.remove('dragging') })

    this.el.addEventListener('drop', event => {
      event.preventDefault()
      const files = event.dataTransfer.files

      if (files.length > 1) {
        console.log('too many files!')
        return false
      }

      const f = files.item(0)
      this.upload(f)
    })
  },

  upload(f) {
    const reader = new FileReader()
    reader.onload = (event) => {
      this.pushEventTo(this.target, 'drop_svg', { code: event.target.result })
    }
    reader.readAsText(f)
  }
})