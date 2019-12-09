module.exports = {
  plugins: [
    // require('postcss-easy-import')({ prefix: '_', extensions: ['pcss', 'scss', 'css'] }),
    require('@univers-agency/europacss'),
    require('autoprefixer')()
    // require('css-mqgroup')({ sort: true })
  ]
}
