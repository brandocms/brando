import DOMPurify from 'dompurify'

const tags = ['p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 's', 'strike', 'u', 'code', 'pre', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'a', 'sub', 'sup', 'ul', 'ol', 'li', 'hr']
const attributes = ['href', 'class', 'id', 'style', 'start', 'data-type', 'data-footnote-uid', 'data-identifier-id', 'data-brando-note']

// This is a display copy. Never put sanitized or normalized preview markup
// back into the input: an untouched field must keep its original value.
export default class RichTextPreview {
  constructor(target, activate, openFootnote) {
    this.el = document.createElement('div')
    this.el.className = 'tiptap-preview'
    const actions = document.createElement('div')
    actions.className = 'tiptap-preview-actions'
    this.button = document.createElement('button')
    this.button.type = 'button'
    this.button.className = 'tiptap-activate'
    this.label = document.createElement('span')
    this.button.append(this.label)
    actions.append(this.button)
    this.content = document.createElement('div')
    this.content.className = 'tiptap ProseMirror tiptap-preview-content'
    this.content.contentEditable = 'false'
    this.el.append(this.content, actions)
    this.el.addEventListener('click', event => {
      event.preventDefault()
      if (this.button.disabled) return
      const note = event.target.closest('.tiptap-footnote')
      if (note) openFootnote(note.dataset.footnoteUid, note.dataset.number)
      else activate(this.content.contains(event.target) ? event : null)
    })
    target.append(this.el)
  }

  update(html, labels, a11y) {
    this.label.textContent = labels.editText
    this.button.setAttribute('aria-label', `${labels.editText}: ${a11y['aria-label']}`)
    this.button.setAttribute('aria-describedby', a11y['aria-describedby'])
    this.button.setAttribute('aria-invalid', a11y['aria-invalid'])
    if (this.html === html && this.placeholder === labels.placeholder) return false
    this.html = html
    this.placeholder = labels.placeholder
    const fragment = DOMPurify.sanitize(html, { ALLOWED_TAGS: tags, ALLOWED_ATTR: attributes, ALLOW_DATA_ATTR: false, RETURN_DOM_FRAGMENT: true })
    fragment.querySelectorAll('[style]').forEach(node => {
      const color = node.style.color, align = node.style.textAlign
      node.removeAttribute('style')
      if (color) node.style.color = color
      if (['left', 'center', 'right', 'justify'].includes(align)) node.style.textAlign = align
    })
    fragment.querySelectorAll('a').forEach(node => node.setAttribute('tabindex', '-1'))
    fragment.querySelectorAll('sup[data-footnote-uid], span[data-footnote-uid]').forEach(node => {
      const marker = document.createElement('button')
      marker.type = 'button'
      marker.className = 'tiptap-footnote'
      marker.dataset.footnoteUid = node.dataset.footnoteUid
      marker.textContent = '•'
      node.replaceWith(marker)
    })
    this.content.replaceChildren(fragment)
    if (!this.content.textContent.trim() && !this.content.querySelector('hr')) {
      const placeholder = document.createElement('p')
      placeholder.className = 'tiptap-preview-empty'
      placeholder.textContent = labels.placeholder
      this.content.replaceChildren(placeholder)
    }
    return true
  }

  setLocked(locked) {
    this.button.disabled = locked
    this.el.classList.toggle('is-readonly', locked)
    this.content.querySelectorAll('.tiptap-footnote').forEach(marker => { marker.disabled = locked })
  }

  destroy() { this.el.remove() }
}
