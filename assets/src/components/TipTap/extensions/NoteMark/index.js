import { Mark } from '@tiptap/core'

// An editors' note on a text range (`Brando.Notes`). Stored in the HTML as
// `<span data-brando-note="<id>">`, which the renderers strip, so it never
// reaches the site or the live preview. Every editor parses it, so editing
// marked text anywhere keeps the mark; only "Add note" creates one.
//
// It is unstyled here: the admin highlights the marks of open notes with
// one stylesheet keyed on their ids (`assets/src/Notes`).
export default Mark.create({
  name: 'noteAnchor',
  inclusive: false,
  // Notes can overlap: a range may carry several marks with different ids.
  excludes: '',
  keepOnSplit: true,

  addAttributes() {
    return {
      id: {
        default: null,
        parseHTML: element => element.getAttribute('data-brando-note'),
        renderHTML: attributes => (attributes.id ? { 'data-brando-note': String(attributes.id) } : {}),
      },
    }
  },

  parseHTML() {
    return [{ tag: 'span[data-brando-note]' }]
  },

  renderHTML({ HTMLAttributes }) {
    return ['span', HTMLAttributes, 0]
  },
})
