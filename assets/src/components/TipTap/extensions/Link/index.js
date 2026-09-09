import Link from '@tiptap/extension-link'
import { isAllowedUri, linkRel } from '../../urlPolicy'

export const isButtonLink = attrs => String(attrs.class || '').split(/\s+/).includes('action-button')
export const linkClass = (current, button) => [...new Set([...String(current || '').split(/\s+/).filter(token => token && token !== 'action-button'), ...(button ? ['action-button'] : [])])].join(' ') || null

export default Link.extend({
  addOptions() {
    return { ...this.parent?.(), openOnClick: false, defaultProtocol: 'https', HTMLAttributes: { target: null, rel: null, class: null }, isAllowedUri: (url, ctx) => isAllowedUri(url) && ctx.defaultValidate(url) }
  },
  addAttributes() {
    return { ...this.parent?.(), 'data-identifier-id': { default: null } }
  },
  renderHTML(props) {
    props.HTMLAttributes.rel = linkRel(props.HTMLAttributes.target, props.HTMLAttributes.rel)
    return this.parent(props)
  },
  addCommands() {
    return {
      ...this.parent?.(),
      setButton: attributes => ({ commands }) => commands.setLink({ ...attributes, class: linkClass(attributes.class, true) }),
      toggleButton: attributes => ({ commands, editor }) => isButtonLink(editor.getAttributes('link')) ? commands.unsetLink() : commands.setButton(attributes),
      unsetButton: () => ({ commands }) => commands.unsetLink(),
    }
  },
})
