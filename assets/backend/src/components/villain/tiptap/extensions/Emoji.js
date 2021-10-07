import { Node } from 'tiptap'
import { replaceText } from 'tiptap-commands'
import { Suggestions } from 'tiptap-extensions'

export default class Emojis extends Node {
  get name () {
    return 'emoji'
  }

  get defaultOptions () {
    return {
      matcher: {
        char: ':',
        allowSpaces: false,
        startOfLine: false
      },
      emojiClass: 'emoji',
      suggestionClass: 'emoji-suggestion'
    }
  }

  get schema () {
    return {
      attrs: {
        style: {
          display: {
            default: 'inline-block'
          },
          width: {
            default: '16px'
          },
          height: {
            default: '16px'
          },
          backgroundImage: {
            default: null
          },
          backgroundSize: {
            default: null
          },
          backgroundPosition: {
            default: null
          }
        }
      },
      content: 'inline*',
      group: 'inline',
      inline: true,
      selectable: false,
      parseDOM: [{
        tag: 'span',
        getAttrs: dom => ({
          style: dom.getAttribute('style')
        })
      }],
      toDOM: node => {
        const style = node.attrs.style

        return ['span',
          {
            style: `background-image: ${style.backgroundImage}; background-size: ${style.backgroundSize}; background-position: ${style.backgroundPosition}; display: ${style.display}; width: ${style.width}; height: ${style.height}`
          },
          ['span',
            {
              class: 'd-none'
            },
            'asdf!'
          ]
        ]
      }
    }
  }

  commands ({ schema }) {
    return attrs => replaceText(null, schema.nodes[this.name], attrs)
  }

  get plugins () {
    return [
      Suggestions({
        command: ({ range, attrs, schema }) => replaceText(range, schema.nodes[this.name], attrs),
        appendText: ' ',
        matcher: this.options.matcher,
        items: this.options.items,
        onEnter: this.options.onEnter,
        onChange: this.options.onChange,
        onExit: this.options.onExit,
        onKeyDown: this.options.onKeyDown,
        onFilter: this.options.onFilter,
        suggestionClass: this.options.suggestionClass
      })
    ]
  }
}
