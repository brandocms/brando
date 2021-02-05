module.exports = {
  plugins: [
    require('@univers-agency/europacss'),
    require('autoprefixer')({ grid: 'on' }),
    require('css-mqgroup')({ sort: true }),
    require('postcss-reporter')({ clearReportedMessages: true, throwError: true })
  ]
}
