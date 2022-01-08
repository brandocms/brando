import { Dom } from '@brandocms/jupiter'
import TipTap from '../../components/TipTap/TipTap.svelte'

export default (app) => ({
  mounted () {
    this.mount()    
    app.components.push(this)
    console.log(app.components)
  },

  mount () {
    console.log('==> MOUNTING TIPTAP.')
    const props = this.el.getAttribute('data-props')
    console.log(props)
    const parsedProps = props ? JSON.parse(props) : {}

    this._instance = new TipTap({
      target: Dom.find(this.el, '.tiptap-target'),
      props: parsedProps,
    })
  },

  remount () {
    console.log('remount', this)
    this._instance?.$destroy()
    this.mount()
  },

  destroyed () {
    this._instance?.$destroy()
  }
})