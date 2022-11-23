import { Dom } from '@brandocms/jupiter'
import TipTap from '../../components/TipTap/TipTap.svelte'

export default app => ({
  mounted() {
    this.mount()
    app.components.push(this)
  },

  mount() {
    const $input = Dom.find(this.el, '.tiptap-text')

    this._instance = new TipTap({
      target: Dom.find(this.el, '.tiptap-target'),
      props: {
        content: $input.getAttribute('value') || '',
        extensions: this.el.getAttribute('data-tiptap-extensions')
      }
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
