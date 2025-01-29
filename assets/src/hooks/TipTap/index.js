import { Dom } from '@brandocms/jupiter'
import TipTap from '../../components/TipTap/TipTap.svelte'
import { mount, unmount } from 'svelte'

export default (app) => ({
  mounted() {
    this.mount()
    app.components.push(this)
  },

  mount() {
    const $input = Dom.find(this.el, '.tiptap-text')
    let fName
    if (this.el.dataset.tiptapType === 'rich_text') {
      fName = $input.getAttribute('name')
    } else {
      // it's a block. Try to find the block field.
      fName = this.el
        .closest('.blocks-wrapper')
        ?.getAttribute('data-block-field')
    }

    const reportFocus = () => {
      this.pushEventTo(this.el, 'focus', { field: fName })
    }

    this._instance = mount(TipTap, {
      target: Dom.find(this.el, '.tiptap-target'),
      props: {
        content: $input.getAttribute('value') || '',
        extensions: this.el.getAttribute('data-tiptap-extensions'),
        onFocus: reportFocus,
      },
    })
  },

  remount() {
    unmount(this._instance)
    this.mount()
  },

  destroyed() {
    unmount(this._instance)
  },
})
