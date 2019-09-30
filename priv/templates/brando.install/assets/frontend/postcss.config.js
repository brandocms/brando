module.exports = {
  plugins: [
    require('postcss-easy-import')({
      prefix: '_',
      extensions: ['pcss', 'scss', 'css']
      plugins: [
        require('stylelint')
      ]
    }),
    require('@univers-agency/europacss')
    require('autoprefixer')({ grid: 'on' }),
    require('css-mqgroup')({ sort: true }),
    require('postcss-reporter')({ clearReportedMessages: true, throwError: true })
  ]
}
