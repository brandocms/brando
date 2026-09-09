import DOMPurify from 'dompurify'
import { defaultCapabilities } from '../../config'
import { isAllowedUri, linkRel } from '../../urlPolicy'

const attributes = ['href', 'target', 'rel', 'title', 'class', 'id', 'style', 'start', 'data-type', 'data-identifier-id', 'data-footnote-uid', 'alt']
const tags = ['p', 'br', 'div', 'span', 'strong', 'b', 'em', 'i', 's', 'strike', 'u', 'code', 'pre', 'blockquote', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'a', 'sub', 'sup', 'ul', 'ol', 'li', 'hr', 'table', 'tbody', 'thead', 'tr', 'th', 'td', 'img']
const capability = { strong: 'bold', b: 'bold', em: 'italic', i: 'italic', s: 'strike', strike: 'strike', u: 'underline', code: 'code', pre: 'codeBlock', blockquote: 'blockquote', ul: 'list', ol: 'orderedList', hr: 'horizontalRule', sub: 'sub', sup: 'sup' }

export default class HTMLInputParser {
  constructor({ capabilities = defaultCapabilities, styles = [], scope = null, onWarning = () => {}, preserveReferences = false } = {}) {
    Object.assign(this, { capabilities, styles, scope, onWarning, preserveReferences })
  }

  prepareHTML(html) {
    const safe = DOMPurify.sanitize(html, { ALLOWED_TAGS: tags, ALLOWED_ATTR: attributes, ALLOW_DATA_ATTR: false })
    const doc = new DOMParser().parseFromString(safe, 'text/html')
    const has = key => this.capabilities.includes(key)
    const unwrap = node => node.replaceWith(...node.childNodes)
    const rename = (node, tag) => { const next = doc.createElement(tag); next.append(...node.childNodes); node.replaceWith(next); return next }
    let fallback = false

    // Office editors often encode emphasis only in CSS. Convert it before
    // presentation cleanup; detached DOM operations never execute pasted HTML.
    doc.body.querySelectorAll('[style]').forEach(node => {
      if (has('bold') && /^(bold|[6-9]00)$/.test(node.style.fontWeight)) {
        const strong = doc.createElement('strong'); strong.append(...node.childNodes); node.append(strong)
      }
      if (has('italic') && node.style.fontStyle === 'italic') {
        const em = doc.createElement('em'); em.append(...node.childNodes); node.append(em)
      }
      const color = has('color') ? node.style.color : ''
      const align = has('align') && /^(left|center|right|justify)$/.test(node.style.textAlign) ? node.style.textAlign : ''
      node.removeAttribute('style')
      if (color) node.style.color = color
      if (align) node.style.textAlign = align
    })

    doc.body.querySelectorAll('table').forEach(table => {
      const rows = [...table.querySelectorAll('tr')].map(row => { const p = doc.createElement('p'); p.textContent = [...row.querySelectorAll('td, th')].map(cell => cell.textContent).join(' · '); return p })
      table.replaceWith(...rows); fallback = true
    })
    doc.body.querySelectorAll('img').forEach(node => { node.replaceWith(doc.createTextNode(node.alt || '')); fallback = true })
    const anchorIds = new Set([...this.scope?.querySelectorAll('[id]') || []].map(node => node.id))
    const noteIds = new Set([...this.scope?.querySelectorAll('[data-footnote-uid]') || []].map(node => node.dataset.footnoteUid))
    doc.body.querySelectorAll('*').forEach(node => {
      if (!node.isConnected) return
      const tag = node.tagName.toLowerCase()
      if (node.hasAttribute('data-footnote-uid')) {
        if (this.preserveReferences || noteIds.has(node.dataset.footnoteUid)) return
        node.replaceWith(doc.createTextNode('[note]')); fallback = true; return
      }
      const classes = [...node.classList].filter(name => this.styles.some(style => style.element === tag && style.className === name) || tag === 'a' && name === 'action-button')
      if (classes.length) node.className = classes.join(' ')
      else node.removeAttribute('class')
      if (tag === 'a') {
        const button = node.classList.contains('action-button')
        if (!isAllowedUri(node.getAttribute('href')) || !has(button ? 'button' : 'link')) { unwrap(node); return }
        const rel = linkRel(node.getAttribute('target'), node.getAttribute('rel'))
        if (rel) node.setAttribute('rel', rel)
      }
      if (node.id) {
        if (node.dataset.type !== 'jump-anchor' || !has('jumpAnchor') || anchorIds.has(node.id)) { node.removeAttribute('id'); node.removeAttribute('data-type') }
        else anchorIds.add(node.id)
      }
      const key = /^h[1-6]$/.test(tag) ? tag : capability[tag]
      if (key && !has(key) && !this.styles.some(style => style.element === tag && node.classList.contains(style.className))) {
        if (/^(h[1-6]|pre|blockquote|li)$/.test(tag)) rename(node, 'p')
        else if (tag === 'ul' || tag === 'ol') { [...node.children].forEach(li => rename(li, 'p')); unwrap(node) }
        else unwrap(node)
      }
    })
    if (fallback) this.onWarning('pasteFallback')
    return doc.body.innerHTML
  }

  sanitizeHTML(html) { return this.prepareHTML(html) }
}
