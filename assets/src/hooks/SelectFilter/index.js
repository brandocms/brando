import { Dom, gsap } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    this.$input = Dom.find(this.el, 'input')
    this.$options = Dom.all(this.el.nextElementSibling, '.options-option')
    this.$input.addEventListener('input', e => {
      this.filter(this.$input.value.toLowerCase().trim())
    })
  },

  filter(value) {
    const optionsToHide = this.$options.filter(option => {
      return !this.includes(option.dataset.label, value)
    })
    gsap.set(this.$options, { display: 'block' })
    if (optionsToHide.length) {
      gsap.set(optionsToHide, { display: 'none' })
    }
  },

  includes(str, query) {
    if (str === undefined) str = 'undefined'
    if (str === null) str = 'null'
    if (str === false) str = 'false'
    const text = str.toString().toLowerCase()
    return text.indexOf(query.trim()) !== -1
  },
})