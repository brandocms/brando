export default app => ({
  updated() {
    this.el.dispatchEvent(new Event('input', { bubbles: true }))
  }
})
