
import { Mark, markPasteRule, mergeAttributes } from '@tiptap/core'
import { find } from 'linkifyjs'
import autolink from './helpers/autolink'
import pasteHandler from './helpers/pasteHandler'


export default Mark.create({
  name: 'link',
  priority: 1000,
  keepOnSplit: false,

  inclusive() {
    return this.options.autolink
  },

  addOptions() {
    return {
      openOnClick: false,
      linkOnPaste: true,
      autolink: true,
      HTMLAttributes: {
        target: '_blank',
        rel: 'noopener noreferrer nofollow',
      },
    }
  },

  addAttributes() {
    return {
      href: {
        default: null,
      },
      target: {
        default: this.options.HTMLAttributes.target,
        renderHTML: attributes => {
          if (attributes.href.startsWith('/')) {
            return {
              target: null,
              rel: null
            }
          }
          if (attributes.href.startsWith('#')) {
            return {
              target: null,
              rel: null
            }
          }

          return {
            target: this.options.HTMLAttributes.target,
            rel: this.options.HTMLAttributes.rel
          }
        }
      }
    }
  },

  parseHTML() {
    return [
      { tag: 'a[href]' },
    ]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'a',
      mergeAttributes(this.options.HTMLAttributes, HTMLAttributes),
      0,
    ]
  },

  addCommands() {
    return {
      setLink: attributes => ({ commands }) => {
        return commands.setMark(this.name, attributes)
      },

      toggleLink: attributes => ({ commands }) => {
        return commands.toggleMark(this.name, attributes, { extendEmptyMarkRange: true })
      },

      unsetLink: () => ({ commands }) => {
        return commands.unsetMark(this.name, { extendEmptyMarkRange: true })
      },
    }
  },

  addPasteRules() {
    return [
      markPasteRule({
        find: text => find(text)
          .filter(link => link.isLink)
          .map(link => ({
            text: link.value,
            index: link.start,
            data: link,
          })),
        type: this.type,
        getAttributes: match => ({
          href: match.data?.href,
        }),
      }),
    ]
  },

  addProseMirrorPlugins() {
    const plugins = []

    if (this.options.autolink) {
      plugins.push(autolink({
        type: this.type,
      }))
    }

    if (this.options.linkOnPaste) {
      plugins.push(pasteHandler({
        editor: this.editor,
        type: this.type,
      }))
    }

    return plugins
  },
})