/**
 * Colours the one-line commands in the seeded modules (`.cmd`).
 *
 * A command is an editable text ref, so it is read back as plain text and
 * rebuilt from tokens. Three kinds of line are recognised — a shell command,
 * a Liquid tag and an admin path — which is not worth a highlighter library.
 * Anything else is left exactly as the editor wrote it.
 */

const KINDS = [
  { lang: 'liquid', test: /^\{%.*%\}$/, tokenize: liquid },
  { lang: 'path', test: /^\/\S*$/, tokenize: path },
  { lang: 'shell', test: /^(\$\s*)?mix\b/, tokenize: shell },
]

export default function highlight(root = document) {
  root.querySelectorAll('.cmd').forEach(el => {
    const text = el.textContent.trim()
    const kind = KINDS.find(({ test }) => test.test(text))
    if (!kind) return

    const code = document.createElement('code')
    code.dataset.lang = kind.lang
    kind.tokenize(text).forEach(([type, value]) => code.append(token(type, value)))
    el.replaceChildren(code)
  })
}

function token(type, value) {
  if (!type) return document.createTextNode(value)

  const span = document.createElement('span')
  span.className = `tok-${type}`
  span.textContent = value
  return span
}

// `mix brando.gen --force` → a prompt sigil, the command, a dotted task name
// and dimmed flags, matching the toolbox shell further down the page.
function shell(text) {
  const words = text.replace(/^\$\s*/, '').split(/(\s+)/)

  return [
    ['sigil', '$'],
    [null, ' '],
    ...words.flatMap((word, i) => {
      if (/^\s+$/.test(word)) return [[null, word]]
      if (i === 0) return [[null, word]]
      if (word.startsWith('-')) return [['flag', word]]
      return dotted(word)
    }),
  ]
}

// `{% ref refs.title %}` → dim delimiters, the tag keyword, a dotted argument.
function liquid(text) {
  const [, open, space, keyword, rest, close] = text.match(/^(\{%-?)(\s*)(\S+)(.*?)(\s*-?%\})$/)

  return [
    ['punct', open],
    [null, space],
    ['keyword', keyword],
    ...rest.split(/(\s+)/).flatMap(part => (/^\s*$/.test(part) ? [[null, part]] : dotted(part))),
    ['punct', close],
  ]
}

// `/admin/pages` → dim slashes between the segments.
function path(text) {
  return text
    .split(/(\/)/)
    .filter(Boolean)
    .map(part => (part === '/' ? ['punct', part] : ['name', part]))
}

// Dots are dimmed so the eye reads each segment of a dotted name first.
function dotted(word) {
  return word
    .split(/(\.)/)
    .filter(Boolean)
    .map(part => (part === '.' ? ['punct', part] : ['name', part]))
}
