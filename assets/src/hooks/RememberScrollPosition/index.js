export default (app) => ({
  mounted() {
    this.scrollTop = 0
    this.el.addEventListener('scroll', this.scrollListener.bind(this))
  },

  updated() {
    this.el.scrollTop = this.scrollTop
  },

  destroyed() {
    this.el.removeEventListener('scroll', this.scrollListener.bind(this))
  },

  scrollListener () {
    this.scrollTop = this.el.scrollTop
  }
})