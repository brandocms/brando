module.exports = {
  outputDir: '../../priv/static',
  // assetsDir: '/',
  runtimeCompiler: true,
  // disable hashes in filenames
  // filenameHashing: false,
  pluginOptions: {
    i18n: {
      locale: 'en',
      fallbackLocale: 'en',
      localeDir: 'locales',
      enableInSFC: true
    }
  },

  css: {
    extract: false
  },

  configureWebpack: {
    output: {
      filename: 'js/admin/[name].js',
      chunkFilename: 'js/admin/[name].js'
    }
  },

  transpileDependencies: [
    'brandojs'
  ]
}
