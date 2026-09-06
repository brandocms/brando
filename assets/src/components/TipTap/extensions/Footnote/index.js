import { Node } from '@tiptap/core'

export const renumberFootnotes = (element) => {
  const scope = element.closest('.blocks-wrapper') || element
  const numbers = new Map()
  scope.querySelectorAll('.tiptap-footnote').forEach(marker => {
    const uid = marker.dataset.footnoteUid
    if (!numbers.has(uid)) numbers.set(uid, numbers.size + 1)
    const number = numbers.get(uid)
    marker.textContent = String(number)
    marker.dataset.number = String(number)
    marker.setAttribute('aria-label', `Edit footnote ${number}`)
  })
}

export default Node.create({
  name: 'footnote',
  // A reference is a node, even though its serialized tag is also recognized
  // by the ordinary Superscript mark. Parse it before that generic mark.
  priority: 1000,
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addOptions() { return { onOpen: null } },

  addAttributes() {
    return {
      uid: {
        default: null,
        parseHTML: element => element.getAttribute('data-footnote-uid'),
        renderHTML: attrs => ({ 'data-footnote-uid': attrs.uid }),
      },
    }
  },

  parseHTML() {
    // ProseMirror collects mark rules before node rules. Extension order alone
    // cannot beat Superscript's <sup> rule; the DOM rule needs priority too.
    return [{ tag: 'sup[data-footnote-uid]', priority: 1000 }, { tag: 'span[data-footnote-uid]', priority: 1000 }]
  },
  renderHTML({ HTMLAttributes }) { return ['sup', HTMLAttributes, '•'] },

  addNodeView() {
    return ({ node }) => {
      const dom = document.createElement('button')
      dom.type = 'button'
      dom.contentEditable = 'false'
      dom.className = 'tiptap-footnote'
      dom.dataset.footnoteUid = node.attrs.uid
      dom.textContent = '•'
      dom.setAttribute('aria-label', 'Edit footnote')
      dom.addEventListener('mousedown', event => event.preventDefault())
      dom.addEventListener('click', () => this.options.onOpen?.(node.attrs.uid, dom.dataset.number))
      return { dom, stopEvent: () => true, ignoreMutation: () => true }
    }
  },
})
