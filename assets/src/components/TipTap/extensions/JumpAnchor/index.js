import { Mark, mergeAttributes } from '@tiptap/core'
import { Plugin, PluginKey } from '@tiptap/pm/state'

export default Mark.create({
  name: 'jumpAnchor',
  priority: 10000,
  inclusive: false,
  keepOnSplit: false,

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
      unsetJumpAnchor:
        () =>
        ({ commands }) => {
          return commands.unsetMark(this.name, { extendEmptyMarkRange: true })
        }
    }
  },

  addProseMirrorPlugins() {
    return [new Plugin({
      key: new PluginKey('uniqueJumpAnchors'),
      appendTransaction(transactions, _old, state) {
        if (!transactions.some(tr => tr.docChanged)) return null
        const seen = new Map()
        const tr = state.tr
        state.doc.descendants((node, pos) => {
          if (!node.isInline) return
          const mark = node.marks.find(mark => mark.type.name === 'jumpAnchor')
          if (!mark?.attrs.id) return
          const previousEnd = seen.get(mark.attrs.id)
          if (previousEnd !== undefined && previousEnd !== pos) tr.removeMark(pos, pos + node.nodeSize, mark)
          else seen.set(mark.attrs.id, pos + node.nodeSize)
        })
        return tr.docChanged ? tr : null
      },
    })]
  },
})
