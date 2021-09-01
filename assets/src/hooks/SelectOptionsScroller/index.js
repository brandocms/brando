export default (app) => ({
  mounted() {
    this.scrollTop = 0
    this.el.addEventListener('scroll', e => {
      this.scrollTop = this.el.scrollTop
    })
  },

  updated() {
    this.el.scrollTop = this.scrollTop
  }
})