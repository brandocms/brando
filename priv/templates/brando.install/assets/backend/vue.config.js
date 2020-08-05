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

  configureWebpack: config => {
    config.output.filename = 'js/admin/[name].js'
    config.output.chunkFilename = 'js/admin/[name].js'
    if (process.env.NODE_ENV === 'development') {
      config.devtool = 'eval-source-map'
      config.output.devtoolFallbackModuleFilenameTemplate =
        'webpack:///[resource-path]?[hash]'
      config.output.devtoolModuleFilenameTemplate = info => {
        const isVue = info.resourcePath.match(/\.vue$/)
        const isScript = info.query.match(/type=script/)
        const hasModuleId = info.moduleId !== ''

        // Detect generated files, filter as webpack-generated
        if (
          // Must result from vue-loader
          isVue &&
          // Must not be 'script' files (enough for chrome), or must have moduleId (firefox)
          (!isScript || hasModuleId)
        ) {
          const pathParts = info.resourcePath.split('/')
          const baseName = pathParts[pathParts.length - 1]
          // prepend 'generated-' to filename as well, so it's easier to find desired files via Ctrl+P
          pathParts.splice(-1, 1, `generated-${baseName}`)
          return `webpack-generated:///${pathParts.join('/')}?${info.hash}`
        }
        // If not generated, filter as webpack-vue
        return `webpack-vue:///${info.resourcePath}`
      }
    }
  },

  transpileDependencies: [
    'brandojs'
  ]
}
