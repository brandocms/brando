import { Dom } from '@brandocms/jupiter'

import { Annotation, EditorState } from '@codemirror/state'
import { keymap } from '@codemirror/view'
import { indentWithTab } from '@codemirror/commands'
import { EditorView, basicSetup } from 'codemirror'
import { html } from '@codemirror/lang-html'

const serverUpdate = Annotation.define()

export default (app) => ({
  mounted() {
    this.serverValue = this.el.dataset.value
    this.initialize()
  },

  updated() {
    const value = this.el.dataset.value ?? ''
    if (value === this.serverValue) {
      // A patch may restore the textarea's server HTML while the editor still
      // has a local edit waiting for its debounce. Keep the submitted value in sync.
      this.$input.value = this.view.state.doc.toString()
      return
    }

    this.serverValue = value
    this.$input.value = value
    if (value !== this.view.state.doc.toString()) {
      this.view.dispatch({
        changes: { from: 0, to: this.view.state.doc.length, insert: value },
        annotations: serverUpdate.of(true)
      })
    }
  },

  destroyed() {
    this.view?.destroy()
  },

  syncInput() {
    return (transaction) => {
      this.view.update([transaction])
      if (!transaction.changes.empty && !transaction.annotation(serverUpdate)) {
        this.$input.value = this.view.state.sliceDoc()
        this.$input.dispatchEvent(new Event('input', { bubbles: true }))
      }
    }
  },

  initialize() {
    this.$containerEl = Dom.find(this.el, '.editor')
    this.$input = Dom.find(this.el, 'textarea')

    this.view = new EditorView({
      dispatch: this.syncInput(),
      parent: this.$containerEl,
      state: EditorState.create({
        doc: this.$input.value,
        extensions: [
          basicSetup,
          EditorView.theme({
            '&': {
              fontSize: '13px',
              border: '1px solid #c0c0c0',
            },
            '.cm-content': {
              fontFamily: 'Mono',
              minHeight: '200px',
            },
            '.cm-gutters': {
              minHeight: '200px',
            },
            '.cm-scroller': {
              overflow: 'auto',
              maxHeight: '600px',
            },
          }),
          keymap.of([indentWithTab]),
          EditorState.tabSize.of(4),
          html(),
        ],
      }),
    })
  },
})
