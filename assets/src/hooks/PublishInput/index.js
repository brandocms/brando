export default app => ({
  mounted() {
    console.log('PublishInput — mounted', this.el)
  },
  updated() {
    console.log('PublishInput — updated. Dispatching input event')
    this.el.dispatchEvent(new Event('input', { bubbles: true }))
  }
})
