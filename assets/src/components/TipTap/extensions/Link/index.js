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
  name: 'link',

  priority: 1000,

  inclusive: false,

  defaultOptions: {
    openOnClick: false,
    linkOnPaste: true,
    HTMLAttributes: {
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
        renderHTML: attributes => {
          console.log('renderHTML', attributes)
          if (attributes.href.startsWith('/')) {
            console.log('starts with /')
            return {
              target: null,
              rel: null
            }
          }
          if (attributes.href.startsWith('#')) {
            console.log('starts with #')
            return {
              target: null,
              rel: null
            }
          }

          return {
            target: this.options.HTMLAttributes.target,
            rel: this.options.HTMLAttributes.rel
          }
        },
      },
    }
  },

  parseHTML() {
    return [
      { tag: 'a[href]' },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return ['a', mergeAttributes(this.options.HTMLAttributes, HTMLAttributes), 0]
  },

  addCommands() {
    return {
      setLink: attributes => ({ commands }) => {
        return commands.setMark('link', attributes)
      },
      toggleLink: attributes => ({ commands }) => {
        return commands.toggleMark('link', attributes, { extendEmptyMarkRange: true })
      },
      unsetLink: () => ({ commands }) => {
        return commands.unsetMark('link', { extendEmptyMarkRange: true })
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

              if (!textContent || !textContent.match(pasteRegexExact)) {
                return false
              }

              this.editor.commands.setMark(this.type, {
                href: textContent,
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