// webpack.common.js - common webpack config

// node modules
const path = require('path')
const merge = require('webpack-merge')

// webpack plugins
const CopyWebpackPlugin = require('copy-webpack-plugin')
const WebpackNotifierPlugin = require('webpack-notifier')

// config files
const pkg = require('./package.json')
const settings = require('./webpack.settings.js')

// Configure Babel loader
const configureBabelLoader = browserList => ({
  test: /\.(js|mjs)$/,
  exclude: settings.babelLoaderConfig.exclude,
  use: {
    loader: 'babel-loader',
    options: {
      cacheDirectory: true,
      presets: [
        [
          '@babel/preset-env', {
            modules: false,
            corejs: {
              version: 3,
              proposals: false
            },
            useBuiltIns: 'usage',
            targets: {
              browsers: browserList
            }
          }
        ]
      ],
      plugins: [
        '@babel/plugin-syntax-dynamic-import',
        '@babel/plugin-transform-runtime'
      ]
    }
  }
})

// Configure Entries
const configureEntries = () => {
  const entries = {}
  Object.keys(settings.entries).forEach(key => {
    const val = settings.entries[key]
    entries[key] = path.resolve(__dirname, settings.paths.src.js + val)
  })

  return entries
}

// Configure Font loader
const configureFontLoader = () => ({
  test: /\.(ttf|eot|otf|woff2?)$/i,
  use: [
    {
      loader: 'file-loader',
      options: {
        name: '[path][name].[ext]'
      }
    }
  ]
})

// The base webpack config
const baseConfig = {
  name: pkg.name,
  entry: configureEntries(),
  output: {
    path: path.resolve(__dirname, settings.paths.dist.base),
    publicPath: settings.urls.publicPath()
  },
  module: {
    rules: [
      configureFontLoader()
    ]
  },
  plugins: [
    new WebpackNotifierPlugin({ title: 'Webpack', excludeWarnings: true, alwaysNotify: true })
  ]
}

// Legacy webpack config
const legacyConfig = {
  module: {
    rules: [
      configureBabelLoader(
        Object.keys(pkg.browserslist.legacyBrowsers).map(e => pkg.browserslist.legacyBrowsers[e])
      )
    ]
  }
}

// Modern webpack config
const modernConfig = {
  module: {
    rules: [
      configureBabelLoader(
        Object.keys(pkg.browserslist.modernBrowsers).map(e => pkg.browserslist.modernBrowsers[e])
      )
    ]
  }
}

// Common module exports
// noinspection WebpackConfigHighlighting
module.exports = {
  legacyConfig: merge.strategy({
    module: 'prepend',
    plugins: 'prepend'
  })(
    baseConfig,
    legacyConfig
  ),
  modernConfig: merge.strategy({
    module: 'prepend',
    plugins: 'prepend'
  })(
    baseConfig,
    modernConfig
  )
}
