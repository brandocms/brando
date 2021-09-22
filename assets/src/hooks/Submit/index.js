import { Dom } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.$formWrapper = Dom.find(`#${this.el.dataset.formId}-el`)
    this.$form = Dom.find(this.$formWrapper, 'form')
    
    this.el.addEventListener('click', e => {
      e.preventDefault()
      this.$form.dispatchEvent(new Event('submit', { bubbles: true }))
    })

    this.handleEvent('b:submit', () => {
      this.$form.dispatchEvent(new Event('submit', { bubbles: true }))
    })
  }
})