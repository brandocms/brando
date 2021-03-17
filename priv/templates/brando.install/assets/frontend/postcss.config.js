module.exports = {
  plugins: [
    require('@brandocms/europacss'),
    require('autoprefixer')({ grid: 'on' }),
    require('css-mqgroup')({ sort: true }),
    require('postcss-reporter')({ clearReportedMessages: true, throwError: true })
  ]
}
