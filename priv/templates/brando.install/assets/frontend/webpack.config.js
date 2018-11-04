const path = require('path')
const Webpack = require('webpack')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const OptimizeCSSPlugin = require('optimize-css-assets-webpack-plugin')
const UglifyJsPlugin = require('uglifyjs-webpack-plugin')

const config = require('./package')

const ENV = process.env.NODE_ENV || 'development'
const IS_DEV = ENV === 'development'
const OUTPUT_PATH = path.resolve(__dirname, '..', '..', 'priv', 'static')

const ExtractCSS = new MiniCssExtractPlugin({
  filename: 'css/[name].css'
})

const Define = new Webpack.DefinePlugin({
  APP_NAME: JSON.stringify(config.app_name),
  VERSION: JSON.stringify(config.version),
  ENV: JSON.stringify(ENV)
})

const Copy = new CopyWebpackPlugin([{
  context: './static',
  from: '**/*',
  to: '.'
}, {
  context: './node_modules/font-awesome/fonts',
  from: '*',
  to: './fonts'
}])

var PLUGINS = [
  ExtractCSS,
  Define,
  Copy
]

module.exports = function (env = {}) {
  return {
    target: 'web',
    entry: {
      app: [
        // Set up an ES6-ish environment
        './js/index.js'
      ]
    },

    optimization: {
      minimizer: [
        new UglifyJsPlugin({
          cache: true,
          parallel: true,
          sourceMap: IS_DEV,
          uglifyOptions: {
            mangle: true,
            output: {
              comments: false
            }
          }
        }),
        new OptimizeCSSPlugin({
          cssProcessorPluginOptions: {
            preset: ['default', { discardComments: { removeAll: true } }]
          }
        })
      ],

      splitChunks: {
        cacheGroups: {
          styles: {
            name: 'styles',
            test: /\.css$/,
            chunks: 'all',
            enforce: true
          }
        }
      }
    },

    output: {
      filename: 'js/app.js',
      path: OUTPUT_PATH
    },

    module: {
      rules: [{
        test: /\.js$/,
        exclude: /(node_modules|bower_components)/,
        loader: 'babel-loader'
      },
      {
        test: /\.css$/,
        use: [
          MiniCssExtractPlugin.loader,
          'css-loader'
        ]
      },
      {
        test: /\.scss$/,
        use: [
          MiniCssExtractPlugin.loader,
          'css-loader',
          'postcss-loader',
          'sass-loader'
        ]
      },
      {
        test: /\.(eot|svg|ttf|woff|woff2)$/,
        loader: 'url-loader'
      }]
    },

    plugins: PLUGINS,

    stats: {
      colors: true
    }
  }
}
