import { Dom, gsap } from '@brandocms/jupiter'

const IDLE = 0
const UPLOADING = 1
const UPLOAD_URL = '/admin/api/content/upload/image'

export default (app) => ({
  mounted() {
    this.status = IDLE
    this.uid = this.el.dataset.blockUid
    this.csrfToken = Dom.find('meta[name="csrf-token"]').content
    this.plus = Dom.find(this.el, '.empty .plus')

    this.plusTimeline = gsap.timeline({ repeat: -1 })
    this.plusTimeline.to(this.plus, { rotate: 360, ease: 'none', transformOrigin: '50% 50%' })
    this.plusTimeline.timeScale(0)

    this.$fileInput = Dom.find(this.el, '.file-input')
    this.$fileInput.addEventListener('change', e => {
      e.preventDefault()
      e.stopPropagation()

      if (e.target.files.length && e.target.files.length === 1) {
        this.upload(e.target.files[0])
      }
    })
    this.$uploadCanvas = Dom.find(this.el, '.upload-canvas figure')
    this.$uploadCanvas.addEventListener('click', e => {
      this.$fileInput.click()
    })

    this.$uploadCanvas.addEventListener('drop', event => {
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

  spinPlus () {
    gsap.to(this.plusTimeline, { timeScale: 1 })
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
        this.stopPlus()
        console.error('error uploading', { error: data.error })
      }
    } catch (e) {
      this.status = IDLE
      this.stopPlus()
      console.error('error uploading', { error: e })
    }
  }
})