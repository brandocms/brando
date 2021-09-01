import TipTap from '../../components/TipTap/TipTap.svelte'

export default (app) => ({
  mounted() {
    this.mount()    
    app.components.push(this)
  },

  mount() {
    const props = this.el.getAttribute('data-props')
    const parsedProps = props ? JSON.parse(props) : {}

    this._instance = new TipTap({
      target: this.el,
      props: parsedProps,
    })
  },

  remount() {
    this._instance?.$destroy()
    this.mount()
  },

  destroyed() {
    this._instance?.$destroy()
  }
})