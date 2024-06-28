export default app => ({
  updated() {
    console.log('PublishClosestInput updated —— dispatch input', this.el)
    this.el.querySelector('input').dispatchEvent(new Event('input', { bubbles: true }))
  }
})
