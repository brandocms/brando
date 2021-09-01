import tippy from 'tippy.js'

export default (app) => ({
  mounted() {
    const content = this.el.dataset.content

    tippy(this.el, {
      allowHTML: true,
      trigger: 'click',
      onTrigger(instance, event) {
        event.stopPropagation()
      },
      onUntrigger(instance, event) {
        event.stopPropagation()
      },
      content
    })
  }
})