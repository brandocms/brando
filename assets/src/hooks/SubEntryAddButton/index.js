export default (app) => ({
  mounted() {
    this.el.addEventListener('click', e => {
      this.pushEventTo(this.el, 'add_subentry', {}, () => {
        this.pushEventTo(this.el, 'force_validate')
      })
    })

    this.handleEvent(`b:validate:${this.el.id}`, () => {
      this.el.dispatchEvent(new Event('input', { bubbles: true }))
    })
  }
})