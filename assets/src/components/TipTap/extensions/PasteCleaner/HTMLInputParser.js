import DOMPurify from 'dompurify'

const DEFAULT_SAFE_ATTRIBUTES = [
  'about',
  'accept',
  'action',
  'align',
  'alt',
  'autocomplete',
  'axis',
  'background',
  'bgcolor',
  'border',
  'cellpadding',
  'cellspacing',
  'checked',
  'cite',
  'class',
  'clear',
  // 'color',
  'cols',
  'colspan',
  'content',
  'coords',
  'crossorigin',
  'datatype',
  'datetime',
  'default',
  'dir',
  'disabled',
  'download',
  'enctype',
  'face',
  'for',
  'headers',
  'height',
  'hidden',
  'high',
  'href',
  'hreflang',
  'id',
  'inlist',
  'integrity',
  'ismap',
  'label',
  'lang',
  'list',
  'loop',
  'low',
  'max',
  'maxlength',
  'media',
  'method',
  'min',
  'multiple',
  'name',
  'noshade',
  'novalidate',
  'nowrap',
  'open',
  'optimum',
  'pattern',
  'placeholder',
  'poster',
  'prefix',
  'preload',
  'property',
  'pubdate',
  'radiogroup',
  'readonly',
  'rel',
  'required',
  'resource',
  'rev',
  'reversed',
  'role',
  'rows',
  'rowspan',
  'spellcheck',
  'scope',
  'selected',
  'shape',
  'size',
  'sizes',
  'span',
  'srclang',
  'start',
  'src',
  'srcset',
  'step',
  'summary',
  'tabindex',
  'title',
  'type',
  'typeof',
  'usemap',
  'valign',
  'value',
  'vocab',
  'width',
  'xmlns'
]

const DEFAULT_URI_SAFE_ATTRIBUTES = [
  'about',
  'content',
  'datatype',
  'inlist',
  'prefix',
  'property',
  'rel',
  'resource',
  'rev',
  'typeof',
  'vocab'
]

const DEFAULT_SAFE_TAGS = [
  'a',
  'abbr',
  'acronym',
  'address',
  'area',
  'article',
  'aside',
  'audio',
  'b',
  'bdi',
  'bdo',
  'big',
  'blink',
  'blockquote',
  'body',
  'br',
  'button',
  'canvas',
  'caption',
  'center',
  'cite',
  'code',
  'col',
  'colgroup',
  'content',
  'data',
  'datalist',
  'dd',
  'decorator',
  'del',
  'details',
  'dfn',
  'dir',
  'div',
  'dl',
  'dt',
  'element',
  'em',
  'fieldset',
  'figcaption',
  'figure',
  'font',
  'footer',
  'form',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'head',
  'header',
  'hgroup',
  'hr',
  'html',
  'i',
  'img',
  'input',
  'ins',
  'kbd',
  'label',
  'legend',
  'li',
  'main',
  'map',
  'mark',
  'marquee',
  'menu',
  'menuitem',
  'meter',
  'nav',
  'nobr',
  'ol',
  'optgroup',
  'option',
  'output',
  'p',
  'pre',
  'progress',
  'q',
  'rp',
  'rt',
  'ruby',
  's',
  'samp',
  'section',
  'select',
  'shadow',
  'small',
  'source',
  'spacer',
  'span',
  'strike',
  'strong',
  'sub',
  'summary',
  'sup',
  'table',
  'tbody',
  'td',
  'template',
  'textarea',
  'tfoot',
  'th',
  'thead',
  'time',
  'tr',
  'track',
  'tt',
  'u',
  'ul',
  'var',
  'video',
  'wbr'
]

/**
 * An html input parser for the editor.
 * The parser makes the HTML input safe for usage in the editor.
 * This means it removes any tags, attributes and styling we don't understand.
 * It may also translate attributes and tags to things we do understand.
 *
 */
export default class HTMLInputParser {
  constructor({
    editorView,
    safeAttributes = DEFAULT_SAFE_ATTRIBUTES,
    safeTags = DEFAULT_SAFE_TAGS,
    uriSafeAttributes = DEFAULT_URI_SAFE_ATTRIBUTES
  }) {
    this.safeAttributes = safeAttributes
    this.safeTags = safeTags
    this.uriSafeAttributes = uriSafeAttributes
  }

  /**
   * Takes an html string, preprocesses its nodes and sanitizes the result.
   * Returns the cleaned html string with any extra attributes we need.
   *
   * @method prepareHTML
   * @param htmlString {string}
   */
  prepareHTML(htmlString) {
    // const parser = new DOMParser()
    // const document = parser.parseFromString(htmlString, 'text/html')
    // const bodyElement = document.body
    return this.sanitizeHTML(htmlString)
  }

  /**
   * Takes an HTML string and sanitize it.
   * Returns the sanitized HTML string.
   *
   * @method sanitizeHTML
   * @param html {String}
   */
  sanitizeHTML(html) {
    return DOMPurify.sanitize(html, {
      ALLOWED_TAGS: this.safeTags,
      ALLOWED_ATTR: this.safeAttributes,
      ADD_URI_SAFE_ATTR: this.uriSafeAttributes
    })
  }
}
