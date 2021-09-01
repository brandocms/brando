import { Mark, Plugin } from 'tiptap'
import { updateMark, removeMark } from 'tiptap-commands'
import { getMarkAttrs } from 'tiptap-utils'

export default class ActionButton extends Mark {
  get name () {
    return 'action_button'
  }

  get defaultOptions () {
    return {
      openOnClick: false
    }
  }

  get schema () {
    return {
      attrs: {
        href: {
          default: null
        }
      },
      parseDOM: [
        {
          tag: 'a[class="action-button"]',
          getAttrs: dom => ({
            href: dom.getAttribute('href')
          })
        }
      ],
      toDOM: node => ['a', {
        ...node.attrs,
        class: 'action-button',
        rel: 'noopener noreferrer nofollow',
        target: node.attrs.href.startsWith('/') ? null : '_blank'
      }, 0]
    }
  }

  commands ({ type }) {
    return attrs => {
      if (attrs.href) {
        return updateMark(type, attrs)
      }

      return removeMark(type)
    }
  }

  get plugins () {
    if (!this.options.openOnClick) {
      return []
    }

    return [
      new Plugin({
        props: {
          handleClick: (view, pos, event) => {
            const { schema } = view.state
            const attrs = getMarkAttrs(view.state, schema.marks.link)

            if (attrs.href && event.target instanceof HTMLAnchorElement) {
              event.stopPropagation()
              window.open(attrs.href)
            }
          }
        }
      })
    ]
  }
}
