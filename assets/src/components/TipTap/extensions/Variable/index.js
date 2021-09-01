import {
  Mark,
  markInputRule,
  markPasteRule,
  mergeAttributes,
} from '@tiptap/core'


export const inputRegex = /(?:^|\s)((?:{{)((?:[^}]+))(?:}}))$/gm
export const pasteRegex = /(?:^|\s)((?:{{)((?:[^}]+))(?:}}))/gm

export default Mark.create({
  name: 'variable',

  defaultOptions: {
    HTMLAttributes: {
      class: 'brando-villain-variable'
    },
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', mergeAttributes(this.options.HTMLAttributes, HTMLAttributes), 0]
  },

  addInputRules() {
    return [
      markInputRule(inputRegex, this.type),
    ]
  },

  addPasteRules() {
    return [
      markPasteRule(pasteRegex, this.type),
    ]
  },
})