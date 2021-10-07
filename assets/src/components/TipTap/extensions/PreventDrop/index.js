import { Plugin, PluginKey } from 'prosemirror-state'
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
            tabindex: '0',
          },
          handleDOMEvents: {
            drop: (view, event) => {
              console.log('DROP handleDOMEvents', event)
              event.preventDefault()
              return false
            }
          }
        }
      })
    ]
  }
})