import { Dom } from '@brandocms/jupiter'
import slugify from 'slugify'

export default (app) => ({
  async mounted() {
    this.for = Dom.find(`#${this.el.dataset.slugFor}`)
    this.for.addEventListener('input', e => {
      this.el.value = slugify(this.for.value, { lower: true, strict: true })
    })
  }
})