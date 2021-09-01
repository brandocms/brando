import tippy from 'tippy.js'

export default (app) => ({
  mounted() {
    const content = this.el.dataset.popover
    tippy(this.el, {
      allowHTML: true,
      content
    })
  }
})