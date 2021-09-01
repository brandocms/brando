import {
  Mark,
  markPasteRule,
  mergeAttributes,
} from '@tiptap/core'
import { Plugin, PluginKey } from 'prosemirror-state'

/**
 * A regex that matches any string that contains a link
 */
export const pasteRegex = /https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z]{2,}\b(?:[-a-zA-Z0-9@:%._+~#=?!&/]*)(?:[-a-zA-Z0-9@:%._+~#=?!&/]*)/gi

/**
 * A regex that matches an url
 */
export const pasteRegexExact = /^https?:\/\/(?:www\.)?[-a-zA-Z0-9@:%._+~#=]{1,256}\.[a-zA-Z]{2,}\b(?:[-a-zA-Z0-9@:%._+~#=?!&/]*)(?:[-a-zA-Z0-9@:%._+~#=?!&/]*)$/gi

export default Mark.create({
  name: 'button',
  priority: 1100,
  inclusive: false,

  defaultOptions: {
    linkOnPaste: true,
    HTMLAttributes: {
      class: 'action-button',
      target: '_blank',
      rel: 'noopener noreferrer nofollow',
    },
  },

  addAttributes() {
    return {
      href: {
        default: null,
      },
      target: {
        default: this.options.HTMLAttributes.target,
      },
    }
  },

  parseHTML() {
    return [
      { tag: 'a[class="action-button"]' },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return ['a', mergeAttributes(this.options.HTMLAttributes, HTMLAttributes), 0]
  },

  addCommands() {
    return {
      setButton: attributes => ({ commands }) => {
        return commands.setMark('button', attributes)
      },
      toggleButton: attributes => ({ commands }) => {
        return commands.toggleMark('button', attributes)
      },
      unsetButton: () => ({ commands }) => {
        return commands.unsetMark('button')
      },
    }
  },

  addPasteRules() {
    return [
      markPasteRule(pasteRegex, this.type, match => ({ href: match[0] })),
    ]
  },

  addProseMirrorPlugins() {
    const plugins = []

    if (this.options.linkOnPaste) {
      plugins.push(
        new Plugin({
          key: new PluginKey('handlePasteButton'),
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

              if (!textContent || !textContent.match(pasteRegexExact)) {
                return false
              }

              this.editor.commands.setMark(this.type, {
                href: textContent,
                class: 'action-button'
              })

              return true
            },
          },
        }),
      )
    }

    return plugins
  },
})
