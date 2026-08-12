import { Dom } from '@brandocms/jupiter'
import TipTap from '../../components/TipTap/TipTap.svelte'
import { mount, unmount } from 'svelte'

export default (app) => ({
  mounted() {
    this.mount()
    this.setupLinkHandler()
    this.setupClearHandler()
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

    const onToggleLink = (currentHref, currentTarget, currentIdentifierId) => {
      this.pushEventTo(this.el, 'tiptap_link_dialog', {
        current_href: currentHref || '',
        current_target: currentTarget || null,
        current_identifier_id: currentIdentifierId || null,
        mark_type: 'link',
        tiptap_id: this.el.id,
      })
    }

    const onToggleButton = (currentHref, currentTarget, currentIdentifierId) => {
      this.pushEventTo(this.el, 'tiptap_link_dialog', {
        current_href: currentHref || '',
        current_target: currentTarget || null,
        current_identifier_id: currentIdentifierId || null,
        mark_type: 'button',
        tiptap_id: this.el.id,
      })
    }

    this._editor = null

    this._instance = mount(TipTap, {
      target: Dom.find(this.el, '.tiptap-target'),
      props: {
        // read the property, not getAttribute — LiveView patches update an
        // input's value PROPERTY while the attribute keeps its initial
        // render value, so attribute reads re-boot remounts with stale
        // content (remote-sync applies were invisible in tiptap blocks)
        content: $input.value || '',
        extensions: this.el.getAttribute('data-tiptap-extensions'),
        styles: this.el.getAttribute('data-tiptap-styles'),
        onFocus: reportFocus,
        onToggleLink,
        onToggleButton,
        onEditorCreated: (editor) => { this._editor = editor },
        tiptapInput: $input,
      },
    })
  },

  setupLinkHandler() {
    this.handleEvent(`b:tiptap:set_link:${this.el.id}`, (payload) => {
      const editor = this._editor
      if (!editor) return

      const $input = Dom.find(this.el, '.tiptap-text')
      const markType = payload.mark_type || 'link'

      if (payload.unset) {
        if (markType === 'button') {
          editor.chain().focus().unsetButton().run()
        } else {
          editor.chain().focus().unsetLink().run()
        }
      } else {
        const opts = {
          href: payload.href,
          target: payload.target || null,
          rel: payload.rel || null,
        }

        if (payload.identifier_id) {
          opts['data-identifier-id'] = String(payload.identifier_id)
        } else {
          opts['data-identifier-id'] = null
        }

        if (markType === 'button') {
          opts.class = 'action-button'
          editor.chain().focus().extendMarkRange('button').setButton(opts).run()
        } else {
          editor.chain().focus().extendMarkRange('link').setLink(opts).run()
        }
      }

      // Sync to hidden input
      if ($input) {
        $input.value = editor.getHTML()
        $input.dispatchEvent(new Event('input', { bubbles: true }))
      }
    })
  },

  // `Input.rich_text` with `reset` dispatches this from its revert button.
  // The editor owns the document and only syncs outwards to the hidden input,
  // so clearing the input alone would leave the visible text in place.
  setupClearHandler() {
    this._clearListener = () => {
      const $input = Dom.find(this.el, '.tiptap-text')

      if (this._editor) {
        this._editor.commands.clearContent(true)
      }

      if ($input) {
        $input.value = ''
        $input.dispatchEvent(new Event('input', { bubbles: true }))
      }
    }

    this.el.addEventListener('brando:tiptap:clear', this._clearListener)
  },

  remount() {
    unmount(this._instance)
    this.mount()
    this.setupLinkHandler()
  },

  destroyed() {
    this.el.removeEventListener('brando:tiptap:clear', this._clearListener)
    unmount(this._instance)
  },
})
