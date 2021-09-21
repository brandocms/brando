import { Dom, gsap } from '@brandocms/jupiter'

const IDLE = 0
const UPLOADING = 1
const UPLOAD_URL = '/admin/api/content/upload/image'

export default (app) => ({
  mounted() {
    this.strings = {}
    this.strings.idle = Dom.find(this.el, '.instructions span')
    this.strings.uploading = this.el.dataset.textUploading
    this.status = IDLE
    this.uid = this.el.dataset.blockUid
    this.csrfToken = Dom.find('meta[name="csrf-token"]').content
    this.pluses = Dom.all(this.el, '.upload-canvas .plus')

    this.plusTimeline = gsap.timeline({ repeat: -1 })
    this.plusTimeline.to(this.pluses, { duration: 3, rotate: 360, ease: 'none', transformOrigin: '50% 50%' })
    this.plusTimeline.timeScale(0)

    this.$fileInput = Dom.find(this.el, '.file-input')
    this.$fileInput.addEventListener('change', e => {
      e.preventDefault()
      e.stopPropagation()

      if (e.target.files.length && e.target.files.length === 1) {
        this.upload(e.target.files[0])
      }
    })

    this.$uploadCanvases = Dom.all(this.el, '.upload-canvas')

    this.$uploadCanvases.forEach(uploadCanvas => {
      uploadCanvas.addEventListener('click', e => {
        console.log(e.target.tagName)
        if (e.target.tagName === 'BUTTON') {
          return
        }
        
        if (Dom.hasClass(uploadCanvas, 'empty')) {
          this.$fileInput.click()
        } else {
          e.preventDefault()
        }
      })

      uploadCanvas.addEventListener('dragenter', () => { uploadCanvas.classList.add('dragging') })
      uploadCanvas.addEventListener('dragover', () => { uploadCanvas.classList.add('dragging') })
      uploadCanvas.addEventListener('dragleave', () => { uploadCanvas.classList.remove('dragging') })

      uploadCanvas.addEventListener('drop', event => {
        event.preventDefault()
        const files = event.dataTransfer.files

        if (files.length > 1) {
          console.log('too many files!')
          return false
        }

        const f = files.item(0)
        this.upload(f)
      })
    })
    
  },

  setStatusText () {
    if (this.status === IDLE) {
      Dom.all(this.el, '.instructions span').forEach(sp => {
        sp.innerHTML = this.strings.idle
      })
    } else {
      Dom.all(this.el, '.instructions span').forEach(sp => {
        sp.innerHTML = this.strings.uploading
      })
    }
  },

  spinPlus () {
    gsap.to(this.plusTimeline, { timeScale: 0.009 })
  },

  stopPlus () {
    gsap.to(this.plusTimeline, { timeScale: 0 })
  },


  async upload (f) {
    const formData = new FormData()
    const headers = new Headers()

    headers.append('accept', 'application/json, text/javascript, */*; q=0.01')
    headers.append('x-csrf-token', this.csrfToken)

    formData.append('image', f)
    formData.append('name', f.name)
    formData.append('slug', 'post')
    formData.append('uid', this.uid)

    try {
      this.status = UPLOADING
      this.setStatusText()
      this.spinPlus()
      const response = await fetch(UPLOAD_URL, { headers, method: 'post', body: formData })
      const data = await response.json()

      if (data.status === 200) {
        this.showImages = false
        this.uploading = false
        this.stopPlus()

        const image = data.image
        this.pushEventTo(this.el, 'image_uploaded', { id: image.id })
      } else {
        this.status = IDLE
        this.setStatusText()
        this.stopPlus()
        console.error('error uploading', { error: data.error })
      }
    } catch (e) {
      this.status = IDLE
      this.setStatusText()
      this.stopPlus()
      console.error('error uploading', { error: e })
    }
  }
})