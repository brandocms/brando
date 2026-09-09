import { Plugin, PluginKey } from '@tiptap/pm/state'
import { Extension } from '@tiptap/core'

export default Extension.create({
  name: 'preventDrop',

  addProseMirrorPlugins() {
    const { editor } = this

    return [
      new Plugin({
        key: new PluginKey('preventDrop'),
        props: {
          attributes: {
            tabindex: '0'
          },
          handleDOMEvents: {
            drop: (view, event) => {
              event.preventDefault()
              return false
            }
          }
        }
      })
    ]
  }
})
