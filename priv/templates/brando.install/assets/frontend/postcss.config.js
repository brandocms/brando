module.exports = {
  plugins: [
    require('@brandocms/europacss'),
    require('postcss-reporter')({
      clearReportedMessages: true,
      throwError: false,
    }),
  ],
}
