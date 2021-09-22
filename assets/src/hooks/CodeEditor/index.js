import { Dom } from '@brandocms/jupiter'
import { EditorState, EditorView, basicSetup } from '@codemirror/basic-setup'
import { keymap } from '@codemirror/view'
import { indentWithTab } from '@codemirror/commands'
import { html } from '@codemirror/lang-html'


export default (app) => ({
  mounted() {
    this.initialize()    
  },

  updated() {
    if (this._value !== this.$input.value) {
      this._value = this.$input.value
      const transaction = this.view.state.update({ changes: { from: 0, to: this.view.state.doc.length, insert: this._value }})
      const update = this.view.state.update(transaction)
      this.view.update([update])
    }
  }, 

  destroyed () {
    this.editor?.destroy()
  },

  syncInput () {
    return transaction => {
      this.view.update([transaction])
      if (!transaction.changes.empty) {
        this.$input.value = this.view.state.sliceDoc()
        this.$input.dispatchEvent(new Event('input', { bubbles: true }))
      }
    }
  },

  initialize () {
    this.$containerEl = Dom.find(this.el, '.editor')
    this.$input = Dom.find(this.el, 'textarea')
    this._value = this.$input.value

    this.view = new EditorView({
      dispatch: this.syncInput(),
      parent: this.$containerEl,
      state: EditorState.create({ 
        doc: this.$input.value, 
        extensions: [
          keymap.of([indentWithTab]),
          EditorView.theme({
            '&': {
              fontSize: '13px',
              border: '1px solid #c0c0c0'
            },
              '.cm-content': {
              fontFamily: 'Mono',
              minHeight: '200px'
            },
              '.cm-gutters': {
              minHeight: '200px'
            },
              '.cm-scroller': {
              overflow: 'auto',
              maxHeight: '600px'
            }
          }),
          EditorState.tabSize.of(16), 
          basicSetup,
          html()
        ]
      })      
    })
  }
})