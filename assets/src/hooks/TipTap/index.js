import { Dom } from '@brandocms/jupiter'
import TipTap from '../../components/TipTap/TipTap.svelte'
import { mount, unmount } from 'svelte'
import { renumberFootnotes } from '../../components/TipTap/extensions/Footnote'

export default (app) => ({
  mounted() {
    this.mount()
    this.setupLinkHandler()
    this.setupClearHandler()
    this.setupFootnoteHandler()
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
        onBlur: () => {
          if (this.el.dataset.footnotes === 'true' || this.el.closest('.block-slot-drawer')) {
            this.commitInput()
          }
        },
        onToggleLink,
        onToggleButton,
        footnotes: this.el.dataset.footnotes === 'true',
        onOpenFootnote: (uid, number) => {
          this.pushEventTo(this.el, uid ? 'open_footnote' : 'create_footnote', {
            uid,
            number,
            ref_name: this.el.dataset.footnoteRef,
            field: this.el.dataset.footnoteField,
            tiptap_id: this.el.id,
          })
        },
        onEditorCreated: (editor) => {
          this._editor = editor
          queueMicrotask(() => renumberFootnotes(this.el))
        },
        tiptapInput: $input,
      },
    })
    queueMicrotask(() => renumberFootnotes(this.el))
  },

  updated() {
    renumberFootnotes(this.el)
  },

  setupFootnoteHandler() {
    this.handleEvent(`b:tiptap:insert_footnote:${this.el.id}`, ({ uid, restore }) => {
      // Keep the saved ProseMirror selection, but leave focus in the drawer
      // which has just opened above this editor.
      const chain = this._editor?.chain()
      if (restore) chain?.focus()
      chain?.insertContent({ type: 'footnote', attrs: { uid } }).run()
      renumberFootnotes(this.el)
      this.commitInput(() => {
        const drawer = document.getElementById(`block-slot-drawer-${uid}`)
        if (drawer?.classList.contains('visible')) {
          drawer.querySelector('[contenteditable="true"]')?.focus()
        }
      })
    })
  },

  commitInput(onCommitted = () => {}) {
    const input = this.el.querySelector('.tiptap-text')
    const form = input?.form
    if (!form || !this._editor) return
    input.value = this._editor.getHTML()
    // Drawer navigation must not race the 300ms typing debounce. Use exactly
    // the owning form's normal validation params, including sibling fields.
    const fields = Array.from(new FormData(form)).filter(([, value]) => typeof value === 'string')
    this.pushEventTo(this.el, 'commit_tiptap', {
      form: new URLSearchParams(fields).toString(),
      target: input.name.match(/[^\[\]]+/g),
    }, onCommitted)
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
