import { Extension, Mark, mergeAttributes } from '@tiptap/core'
import StarterKit from '@tiptap/starter-kit'
import { TextStyleKit } from '@tiptap/extension-text-style'
import Typography from '@tiptap/extension-typography'
import Subscript from '@tiptap/extension-subscript'
import Superscript from '@tiptap/extension-superscript'
import TextAlign from '@tiptap/extension-text-align'
import { Focus, Placeholder } from '@tiptap/extensions'
import Link from './extensions/Link'
import JumpAnchor from './extensions/JumpAnchor'
import PreventDrop from './extensions/PreventDrop'
import Footnote from './extensions/Footnote'

// Keep parsing/rendering legacy nodes. Restrict authoring at the extension's
// commands and rules, instead of dropping its schema and losing stored HTML.
export function authoringGate(extension, enabled, commandAllowed = () => enabled) {
  return extension.extend({
    addKeyboardShortcuts() { return enabled ? this.parent?.() || {} : {} },
    addInputRules() { return enabled ? this.parent?.() || [] : [] },
    addPasteRules() { return enabled ? this.parent?.() || [] : [] },
    addCommands() {
      return Object.fromEntries(Object.entries(this.parent?.() || {}).map(([name, command]) => [name, (...args) => props => {
        if (!/^(unset|reset|lift)/.test(name) && !commandAllowed(name, args)) return false
        return command(...args)(props)
      }]))
    },
  })
}

const StyledNodes = Extension.create({
  name: 'styledNodes',
  addGlobalAttributes() {
    return [{ types: ['paragraph', 'heading'], attributes: { class: { default: null, parseHTML: el => el.getAttribute('class'), renderHTML: attrs => attrs.class ? { class: attrs.class } : {} } } }]
  },
})

const LegacySpanStyle = Mark.create({
  name: 'legacySpanStyle',
  priority: 50,
  addAttributes() { return { class: { default: null } } },
  parseHTML() { return [{ tag: 'span[class]:not([data-type])' }] },
  renderHTML({ HTMLAttributes }) { return ['span', HTMLAttributes, 0] },
})

export function createExtensions({ capabilities, styles, footnoteLabels, onOpenFootnote, placeholder = '', typography = {} }) {
  const has = key => capabilities.includes(key)
  const capabilityFor = { bold: 'bold', italic: 'italic', bulletList: 'list', orderedList: 'orderedList', blockquote: 'blockquote', code: 'code', codeBlock: 'codeBlock', horizontalRule: 'horizontalRule', underline: 'underline', strike: 'strike' }
  const kit = StarterKit.extend({
    addExtensions() {
      return this.parent().map(extension => {
        if (extension.name === 'heading') {
          // Configured levels constrain input rules/shortcuts. The parser is
          // deliberately widened again so old H5/H6 remain intact.
          const levels = [1, 2, 3, 4, 5, 6].filter(level => has(`h${level}`) || styles.some(style => style.element === `h${level}`))
          const heading = extension.configure({ levels }).extend({
            parseHTML() { return [1, 2, 3, 4, 5, 6].map(level => ({ tag: `h${level}`, attrs: { level } })) },
            renderHTML({ node, HTMLAttributes }) { return [`h${node.attrs.level}`, mergeAttributes(this.options.HTMLAttributes, HTMLAttributes), 0] },
          })
          return authoringGate(heading, levels.length > 0, (_name, args) => levels.includes(args[0]?.level))
        }
        const key = capabilityFor[extension.name]
        return key ? authoringGate(extension, has(key)) : extension
      })
    },
  }).configure({ link: false, dropcursor: false })
  const textStyleKit = TextStyleKit.extend({
    addExtensions() {
      return this.parent().map(extension => extension.name === 'textStyle' ? extension : authoringGate(extension, extension.name === 'color' && has('color')))
    },
  })
  return [
    kit, StyledNodes, LegacySpanStyle,
    ...styles.filter(style => style.mode === 'mark').map(style => Mark.create({
      name: style.markName,
      addAttributes() { return { class: { default: style.className } } },
      parseHTML() { return [{ tag: `span.${style.className}` }] },
      renderHTML({ HTMLAttributes }) { return ['span', HTMLAttributes, 0] },
    })),
    ...(has('smartText') ? [Typography.configure(typography)] : []),
    authoringGate(Link.configure({ autolink: has('link'), linkOnPaste: has('link') }), has('link') || has('button'), (name, args) => name.includes('Button') ? has('button') : String(args[0]?.class || '').split(/\s+/).includes('action-button') ? has('button') : has('link')),
    authoringGate(Subscript, has('sub')),
    authoringGate(Superscript, has('sup')),
    authoringGate(JumpAnchor, has('jumpAnchor')),
    Focus.configure({ className: 'has-focus', mode: 'shallowest' }),
    Placeholder.configure({ placeholder }),
    PreventDrop,
    Footnote.configure({ onOpen: onOpenFootnote, editLabel: footnoteLabels.edit }),
    textStyleKit,
    authoringGate(TextAlign.configure({ types: ['heading', 'paragraph'] }), has('align')),
  ]
}

export function removeTextFormatting(editor, styles) {
  const marks = ['bold', 'italic', 'underline', 'strike', 'code', 'subscript', 'superscript', 'textStyle', 'legacySpanStyle', ...styles.filter(style => style.mode === 'mark').map(style => style.markName)]
  return marks.reduce((chain, mark) => chain.unsetMark(mark), editor.chain().focus()).run()
}
