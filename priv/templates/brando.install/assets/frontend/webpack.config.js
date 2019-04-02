const path = require('path')
const Webpack = require('webpack')
const ExtractCssChunks = require('extract-css-chunks-webpack-plugin')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const OptimizeCSSPlugin = require('optimize-css-assets-webpack-plugin')
const TerserPlugin = require('terser-webpack-plugin')
const SpeedMeasurePlugin = require('speed-measure-webpack-plugin')
const config = require('./package')

const ENV = process.env.NODE_ENV || 'development'
const IS_DEV = ENV === 'development'
const IS_PROD = ENV === 'production'

const OUTPUT_PATH = path.resolve(__dirname, '..', '..', 'priv', 'static')
const smp = new SpeedMeasurePlugin()

const ExtractCSS = new MiniCssExtractPlugin({ filename: 'css/[name].css' })

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

var PLUGINS = IS_PROD
  ? [ExtractCSS,
    Define,
    Copy
  ]
  : [
    new ExtractCssChunks(
      {
        // Options similar to the same options in webpackOptions.output
        // both options are optional
        filename: '[name].css',
        orderWarning: true // Disable to remove warnings about conflicting order between imports
      }
    ),
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

  devServer: {
    port: 9999,
    disableHostCheck: true,
    headers: {
      'Access-Control-Allow-Origin': '*'
    }
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

  output: IS_PROD
    ? {
      filename: 'js/app.js',
      path: OUTPUT_PATH
    }
    : {
      path: path.resolve(__dirname, 'public'),
      filename: 'app.js',
      publicPath: 'http://localhost:9999/'
    },

  module: {
    rules: [
      IS_PROD
        ? {
          test: /\.js$/,
          exclude: /node_modules(?!\/jupiter)/,
          loader: 'babel-loader'
        }
        : {
          test: /\.js$/,
          exclude: /node_modules(?!\/(jupiter|normalize-url|prepend-http|sort-keys))/,
          loader: 'babel-loader'
        },
      IS_PROD
        ? {
          test: /\.(sa|sc|c)ss$/,
          use: [
            MiniCssExtractPlugin.loader,
            'css-loader',
            'postcss-loader',
            'sass-loader'
          ]
        }
        : {
          test: /\.(sa|sc|c)ss$/,
          use: [
            {
              loader: ExtractCssChunks.loader,
              options: {
                hot: true, // if you want HMR - we try to automatically inject hot reloading but if it's not working, add it to the config
                reloadAll: true // when desperation kicks in - this is a brute force HMR flag
              }
            },
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
