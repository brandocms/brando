const path = require('path')
const Webpack = require('webpack')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const OptimizeCSSPlugin = require('optimize-css-assets-webpack-plugin')
const TerserPlugin = require('terser-webpack-plugin')
const SpeedMeasurePlugin = require('speed-measure-webpack-plugin')
const config = require('./package')

const ENV = process.env.NODE_ENV || 'development'
const IS_DEV = ENV === 'development'
const OUTPUT_PATH = path.resolve(__dirname, '..', '..', 'priv', 'static')
const smp = new SpeedMeasurePlugin()

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

const cfg = {
  target: 'web',
  entry: {
    app: [
      './js/index.js'
    ]
  },

  optimization: {
    minimizer: [
      new TerserPlugin({
        cache: true,
        parallel: true,
        sourceMap: IS_DEV,
        terserOptions: {
          mangle: true,
          toplevel: true,
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
    rules: [
      {
        test: /\.js$/,
        exclude: /node_modules(?!\/jupiter)/,
        loader: 'babel-loader'
      },
      {
        test: /\.(sa|sc|c)ss$/,
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
      }
    ]
  },

  plugins: PLUGINS,

  stats: {
    colors: true
  }
}

module.exports = smp.wrap(cfg)
