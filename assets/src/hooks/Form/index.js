export default (app) => ({
  mounted() {
    this.$form = this.el.querySelector('form')
    this.$input = this.$form.querySelector('input')
    this.$input.dispatchEvent(new Event('input', { bubbles: true }))

    this.handleEvent(`b:validate`, () => {
      this.$input.dispatchEvent(new Event('input', { bubbles: true }))
    })
  }
})