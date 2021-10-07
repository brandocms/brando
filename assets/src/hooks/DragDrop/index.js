export default (app) => ({
  mounted() {
    this.el.addEventListener('dragenter', this.highlight.bind(this), false)
    this.el.addEventListener('dragover', this.highlight.bind(this), false)
    this.el.addEventListener('dragleave', this.unhighlight.bind(this), false)
    this.el.addEventListener('drop', this.unhighlight.bind(this), false)
  },

  highlight (e) {
    this.el.classList.add('dragging')
  },

  unhighlight (e) {
    this.el.classList.remove('dragging')
  }
})