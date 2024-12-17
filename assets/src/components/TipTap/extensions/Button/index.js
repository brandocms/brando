import { Mark, mergeAttributes } from '@tiptap/core'

export default Mark.create({
  name: 'button',
  priority: 1000,
  keepOnSplit: false,
  exitable: true,

  parseHTML() {
    return [{ tag: 'a[class="action-button"]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return [
      'a',
      mergeAttributes(
        {
          class: 'action-button',
          target: '_blank',
          rel: 'noopener noreferrer nofollow',
        },
        HTMLAttributes
      ),
      0,
    ]
  },

  addOptions() {
    return {
      openOnClick: true,
      linkOnPaste: true,
      autolink: true,
      protocols: [],
      defaultProtocol: 'http',
      HTMLAttributes: {
        target: '_blank',
        rel: 'noopener noreferrer nofollow',
        class: 'action-button',
      },
      validate: (url) => !!url,
    }
  },

  addAttributes() {
    return {
      href: {
        default: null,
      },
    }
  },

  addCommands() {
    return {
      setButton:
        (attributes) =>
        ({ chain }) => {
          return chain()
            .setMark(this.name, attributes)
            .setMeta('preventAutolink', true)
            .run()
        },

      toggleButton:
        (attributes) =>
        ({ chain }) => {
          return chain()
            .toggleMark(this.name, attributes, { extendEmptyMarkRange: true })
            .setMeta('preventAutolink', true)
            .run()
        },

      unsetButton:
        () =>
        ({ chain }) => {
          return chain()
            .unsetMark(this.name, { extendEmptyMarkRange: true })
            .setMeta('preventAutolink', true)
            .run()
        },
    }
  },
})
