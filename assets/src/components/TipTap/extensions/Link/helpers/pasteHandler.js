import { Plugin, PluginKey } from 'prosemirror-state'
import { find } from 'linkifyjs'

export default function pasteHandler(options) {
  return new Plugin({
    key: new PluginKey('handlePasteLink'),
    props: {
      handlePaste: (view, event, slice) => {
        const { state } = view
        const { selection } = state
        const { empty } = selection

        if (empty) {
          return false
        }

        let textContent = ''

        slice.content.forEach(node => {
          textContent += node.textContent
        })

        const link = find(textContent).find(item => item.isLink && item.value === textContent)

        if (!textContent || !link) {
          return false
        }

        options.editor.commands.setMark(options.type, {
          href: link.href,
        })

        return true
      },
    },
  })
}