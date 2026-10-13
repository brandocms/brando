// Europa's at-rules write rules and declarations with no source file of their
// own: the base styles it parses from normalize.css, the output of @space,
// @font and the like. Vite resolves a declaration's url() from its file, and
// warns that "a PostCSS plugin did not pass the `from` option" when there is
// none. They belong to the file whose at-rule wrote them, so each takes the
// source of the nearest node around it that has one.
const sourceFromFile = () => ({
  postcssPlugin: 'brando-source-from-file',
  OnceExit(root) {
    root.walk(node => {
      if (node.source?.input?.file) return
      let parent = node.parent
      while (parent && !parent.source?.input?.file) parent = parent.parent
      if (parent) node.source = parent.source
    })
  }
})
sourceFromFile.postcss = true

module.exports = {
  plugins: [
    require('@brandocms/europacss'),
    require('autoprefixer')(),
    sourceFromFile()
  ]
}
