
import { Mark } from 'tiptap'
import { toggleMark, markInputRule, markPasteRule } from 'tiptap-commands'

export default class Arrow extends Mark {
  get name () {
    return 'arrow'
  }

  get defaultOptions () {
    return {
      directions: ['u', 'd', 'l', 'r']
    }
  }

  get schema () {
    return {
      attrs: {
        direction: {
          default: 'r'
        }
      },
      parseDOM: this.options.directions
        .map(direction => ({
          tag: `span.arrow-${direction}`,
          attrs: { direction }
        })),
      toDOM: node => ['span', { class: `arrow-${node.attrs.direction}` }]
    }
  }

  keys ({ type }) {
    return {
      'Mod-`': toggleMark(type)
    }
  }

  commands ({ type }) {
    return () => toggleMark(type)
  }

  inputRules ({ type }) {
    return this.options.directions.map(direction => markInputRule(
      new RegExp(`&(${direction})arr;$`),
      type,
      () => ({ direction })
    ))
  }
}
