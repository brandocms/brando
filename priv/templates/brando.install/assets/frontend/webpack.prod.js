/* eslint-disable compat/compat */
// webpack.prod.js - production builds
const LEGACY_CONFIG = 'legacy'
const MODERN_CONFIG = 'modern'

// node modules
const git = require('git-rev-sync')
const glob = require('glob-all')
const merge = require('webpack-merge')
const moment = require('moment')
const path = require('path')
const webpack = require('webpack')

// webpack plugins
const { BundleAnalyzerPlugin } = require('webpack-bundle-analyzer')
const { DuplicatesPlugin } = require('inspectpack/plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const { CleanWebpackPlugin } = require('clean-webpack-plugin')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const OptimizeCSSAssetsPlugin = require('optimize-css-assets-webpack-plugin')
const PurgecssPlugin = require('purgecss-webpack-plugin')
const TerserPlugin = require('terser-webpack-plugin')
const WhitelisterPlugin = require('purgecss-whitelister')

// config files
const common = require('./webpack.common.js')
const pkg = require('./package.json')
const settings = require('./webpack.settings.js')

// custom extractor for PurgeCSS
class PHXExtractor {
  static extract (content) {
    return content.match(/[A-Za-z0-9-_:/]+/g) || []
  }
}

// Configure file banner
const configureBanner = () => ({
  banner: [
    '/*!',
    ` * @project        ${settings.name}`,
    ' * @name           [filebase]',
    ` * @author         ${pkg.author.name}`,
    ` * @build          ${moment().format('llll')} ET`,
    ` * @copyright      Copyright (c) ${moment().format('YYYY')} ${settings.copyright}`,
    ' *',
    ' */',
    ''
  ].join('\n'),
  raw: true
})

// Configure Bundle Analyzer
const configureBundleAnalyzer = buildType => {
  if (buildType === LEGACY_CONFIG) {
    return {
      analyzerMode: 'static',
      reportFilename: 'report-legacy.html',
      openAnalyzer: false
    }
  }
  if (buildType === MODERN_CONFIG) {
    return {
      analyzerMode: 'static',
      reportFilename: 'report-modern.html',
      openAnalyzer: false
    }
  }
}

// Configure Clean webpack
const configureCleanWebpack = () => ({
  cleanOnceBeforeBuildPatterns: settings.paths.dist.clean,
  verbose: false,
  dry: false
})

const configureCopyWebpackPlugin = () => [
  {
    context: './static',
    from: '**/*',
    to: './', // + prefix,
    force: true
  }
]

// Configure Image loader
const configureImageLoader = buildType => {
  if (buildType === LEGACY_CONFIG) {
    return {
      test: /\.(png|jpe?g|gif|svg|webp)$/i,
      use: [
        {
          loader: 'ignore-loader'
        }
      ]
    }
  }
  if (buildType === MODERN_CONFIG) {
    return {
      test: /\.(png|jpe?g|gif|svg|webp)$/i,
      use: [
        {
          loader: 'file-loader',
          options: {
            name: '[path][name].[ext]'
          }
        }
      ]
    }
  }
}

// Configure optimization
const configureOptimization = buildType => {
  if (buildType === LEGACY_CONFIG) {
    return {
      splitChunks: {
        cacheGroups: {
          default: false,
          common: false,
          styles: {
            name: settings.vars.cssName,
            test: /\.(pcss|css)$/,
            chunks: 'all',
            enforce: true
          }
        }
      },
      minimizer: [
        new TerserPlugin(
          configureTerser()
        ),
        /* only need css optimizer here, since we ignore MODERN for css */
        new OptimizeCSSAssetsPlugin({
          cssProcessorOptions: {
            map: {
              inline: false,
              annotation: true
            },
            safe: true,
            discardComments: true
          }
        })
      ]
    }
  }
  if (buildType === MODERN_CONFIG) {
    return {
      minimizer: [
        new TerserPlugin(
          configureTerser()
        )
      ]
    }
  }
}

// Configure Postcss loader
const configurePostcssLoader = buildType => {
  if (buildType === LEGACY_CONFIG) {
    return {
      test: /\.(sa|sc|pc|c)ss$/,
      use: [
        MiniCssExtractPlugin.loader,
        {
          loader: 'css-loader',
          options: {
            importLoaders: 1,
            sourceMap: true
          }
        },
        {
          loader: 'resolve-url-loader'
        },
        {
          loader: 'postcss-loader',
          options: {
            ident: 'postcss',
            sourceMap: true
          }
        }
      ]
    }
  }
  // Don't generate CSS for the modern config in production
  if (buildType === MODERN_CONFIG) {
    return {
      test: /\.(sa|sc|pc|c)ss$/,
      loader: 'ignore-loader'
    }
  }
}

// Configure PurgeCSS
const configurePurgeCss = () => {
  const paths = []
  // Configure whitelist paths
  for (const [, value] of Object.entries(settings.purgeCssConfig.paths)) {
    paths.push(path.join(__dirname, value))
  }

  return {
    paths: glob.sync(paths),
    whitelist: WhitelisterPlugin(settings.purgeCssConfig.whitelist),
    whitelistPatterns: settings.purgeCssConfig.whitelistPatterns,
    extractors: [
      {
        extractor: PHXExtractor,
        extensions: settings.purgeCssConfig.extensions
      }
    ]
  }
}

// Configure terser
const configureTerser = () => ({
  cache: true,
  parallel: true,
  sourceMap: true,
  terserOptions: {
    mangle: true,
    toplevel: true,
    safari10: true,
    output: {
      comments: false
    }
  }
})

// Production module exports
module.exports = [
  merge(
    common.legacyConfig,
    {
      entry: {
        app: [
          './js/polyfills.legacy.js',
          './js/index.js'
        ]
      },
      output: {
        filename: path.join('./js', '[name].legacy.js')
      },
      mode: 'production',
      devtool: 'source-map',
      optimization: configureOptimization(LEGACY_CONFIG),
      module: {
        rules: [
          configurePostcssLoader(LEGACY_CONFIG),
          configureImageLoader(LEGACY_CONFIG)
        ]
      },
      performance: {
        maxEntrypointSize: 512000,
        maxAssetSize: 800000
      },
      plugins: [
        new MiniCssExtractPlugin({
          path: path.resolve(__dirname, settings.paths.dist.base),
          filename: path.join('./css', '[name].css')
        }),
        // new PurgecssPlugin(
        //   configurePurgeCss()
        // ),
        new webpack.BannerPlugin(
          configureBanner()
        )
      ]
    }
  ),
  merge(
    common.modernConfig,
    {
      entry: {
        app: [
          './js/polyfills.modern.js',
          './js/index.js'
        ]
      },
      output: {
        filename: path.join('./js', '[name].js')
      },
      mode: 'production',
      devtool: 'source-map',
      optimization: configureOptimization(MODERN_CONFIG),
      module: {
        rules: [
          configurePostcssLoader(MODERN_CONFIG),
          configureImageLoader(MODERN_CONFIG)
        ]
      },
      performance: {
        maxEntrypointSize: 512000,
        maxAssetSize: 800000
      },
      plugins: [
        new CleanWebpackPlugin(
          configureCleanWebpack()
        ),
        new CopyWebpackPlugin(
          configureCopyWebpackPlugin()
        ),
        new webpack.BannerPlugin(
          configureBanner()
        ),
        new DuplicatesPlugin({
          // Emit compilation warning or error? (Default: `false`)
          emitErrors: false,
          // Display full duplicates information? (Default: `false`)
          verbose: false
        })
        // new BundleAnalyzerPlugin(
        //   configureBundleAnalyzer(MODERN_CONFIG)
        // )
      ]
    }
  )
]
