import { Mark, mergeAttributes } from '@tiptap/core'

export default Mark.create({
  name: 'jumpAnchor',

  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: element => element.getAttribute('id'),
        renderHTML: attributes => {
          if (!attributes.id) {
            return {}
          }

          return {
            id: attributes.id
          }
        }
      }
    }
  },

  parseHTML() {
    return [
      {
        tag: 'span[data-type="jump-anchor"]'
      }
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes({ 'data-type': 'jump-anchor' }, HTMLAttributes), 0]
  },

  addCommands() {
    return {
      setJumpAnchor:
        attributes =>
        ({ commands }) => {
          return commands.setMark(this.name, attributes)
        },
      getJumpAnchor:
        () =>
        ({ commands }) => {
          if (this.editor.view.state.selection.$from.nodeAfter == null) {
            return
          }

          let node = this.editor.view.state.selection.$from.nodeAfter
          let mark = node.marks.find(mark => mark.type && mark.type.name == 'jumpAnchor')

          if (mark) {
            return mark.attrs.id
          }
        },

      unsetJumpAnchor:
        () =>
        ({ commands }) => {
          console.log('unsetJumpAnchor not written...')
        }
    }
  }
})
