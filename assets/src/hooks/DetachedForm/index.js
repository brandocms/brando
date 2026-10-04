// A form rendered inside another form — a dialog's own form inside the entry
// form. Its `submit` event does not reach LiveView's window listener there, so
// the browser would submit it natively and leave the page. This hook handles
// the submit itself: it pushes `data-submit-event` with the form's values
// (nested by their `name`, like LiveView's own params) to the component that
// renders it, then runs the `data-on-submit` JS (closing the dialog).
const nest = (params, name, value) => {
  const keys = name.replace(/\]/g, '').split('[')
  const last = keys.pop()
  const target = keys.reduce((acc, key) => (acc[key] = acc[key] && typeof acc[key] === 'object' ? acc[key] : {}), params)
  if (last === '') return
  target[last] = value
}

export default () => ({
  mounted() {
    this._onSubmit = event => {
      if (event.target !== this.el) return
      event.preventDefault()
      event.stopPropagation()
      const params = {}
      new FormData(this.el).forEach((value, name) => { if (typeof value === 'string') nest(params, name, value) })
      this.pushEventTo(this.el, this.el.dataset.submitEvent, params)
      if (this.el.dataset.onSubmit) this.js().exec(this.el.dataset.onSubmit)
    }
    this.el.addEventListener('submit', this._onSubmit)
  },

  destroyed() {
    this.el.removeEventListener('submit', this._onSubmit)
  },
})
