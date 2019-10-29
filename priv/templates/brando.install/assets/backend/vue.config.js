module.exports = {
  outputDir: '../../priv/static',
  assetsDir: '/',
  runtimeCompiler: true,
  // disable hashes in filenames
  filenameHashing: false,
  productionSourceMap: false,
  // delete HTML related webpack plugins
  chainWebpack: config => {
    config.plugins.delete('html')
    config.plugins.delete('preload')
    config.plugins.delete('prefetch')

    // GraphQL Loader
    config.module
      .rule('graphql')
      .test(/\.graphql$/)
      .use('graphql-tag/loader')
      .loader('graphql-tag/loader')
      .end()
  },

  css: {
    extract: {
      filename: 'css/admin/[name].css',
      chunkFilename: 'css/admin/[name].css'
    }
  },

  configureWebpack: {
    output: {
      filename: 'js/admin/[name].js',
      chunkFilename: 'js/admin/[name].js'
    }
  }
}
