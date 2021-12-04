import { Dom } from '@brandocms/jupiter'
import slugify from 'slugify'

export default (app) => ({
  async mounted() {
    slugify.extend({ '/': '-' })

    let fors = []
    if (this.el.dataset.slugFor.indexOf(',') > -1) {
      fors = this.el.dataset.slugFor.split(',')      
    } else {
      fors.push(this.el.dataset.slugFor)
    }    

    fors.forEach(f => {
      const el = Dom.find(`#${f}`)      
      el.addEventListener('input', e => {
        const vals = fors.map(f => Dom.find(`#${f}`).value).join('-')   
        this.el.value = slugify(vals, { lower: true, strict: true })
      })
    })
  }
})