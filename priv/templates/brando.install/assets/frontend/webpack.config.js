const path = require('path')
const Webpack = require('webpack')
const ExtractCssChunks = require('extract-css-chunks-webpack-plugin')
const MiniCssExtractPlugin = require('mini-css-extract-plugin')
const CopyWebpackPlugin = require('copy-webpack-plugin')
const WriteFilePlugin = require('write-file-webpack-plugin')
const OptimizeCSSPlugin = require('optimize-css-assets-webpack-plugin')
const TerserPlugin = require('terser-webpack-plugin')
const config = require('./package')

const ENV = process.env.NODE_ENV || 'development'
const isDev = ENV === 'development'
const isProd = ENV === 'production'
const isModern = process.env.BROWSERSLIST_ENV === 'modern'
const isCDN = process.env.UNIVERS_CDN

const OUTPUT_PATH = path.resolve(__dirname, '..', '..', 'priv')

const ExtractCSS = new MiniCssExtractPlugin({
  filename: isModern ? 'static/css/[name].modern.css' : 'static/css/[name].css'
})

const Define = new Webpack.DefinePlugin({
  APP_NAME: JSON.stringify(config.app_name),
  VERSION: JSON.stringify(config.version),
  ENV: JSON.stringify(ENV)
})

const PLUGINS_PROD = [
  ExtractCSS,
  Define,
  new CopyWebpackPlugin([{
    context: './static',
    from: '**/*',
    to: './static',
    ignore: [
      'fonts/'
    ],
    force: true
  }, {
    context: './node_modules/font-awesome/fonts',
    from: '*',
    to: './static/fonts'
  }], { debug: true })
]

const PLUGINS_DEV = [
  new ExtractCssChunks(
    {
      filename: 'static/[name].css',
      orderWarning: true
    }
  ),
  Define,
  new WriteFilePlugin(),
  new CopyWebpackPlugin([{
    context: './static',
    from: '**/*',
    to: './static/',
    force: true
  }, {
    context: './node_modules/font-awesome/fonts',
    from: '*',
    to: './static/fonts'
  }], { debug: true })
]

const OUTPUT_PROD = {
  filename: isModern ? 'static/js/app.modern.js' : 'static/js/app.legacy.js',
  path: OUTPUT_PATH,
  publicPath: isCDN ? '/' + isCDN + '/' : ''
}

const OUTPUT_DEV = {
  futureEmitAssets: false,
  path: OUTPUT_PATH,
  filename: 'static/app.js',
  publicPath: 'http://antennae.local:9999/'
}

const PLUGINS = isProd ? PLUGINS_PROD : PLUGINS_DEV

const cfg = {
  target: 'web',
  entry: {
    app: [
      isModern ? './js/polyfills.modern.js' : './js/polyfills.legacy.js',
      './js/index.js'
    ]
  },

  devtool: isProd ? '' : 'cheap-module-eval-source-map',

  devServer: {
    port: 9999,
    host: '0.0.0.0',
    useLocalIp: true,
    overlay: true,
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
        sourceMap: isDev,
        terserOptions: {
          mangle: true,
          toplevel: true,
          safari10: true,
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

  output: isProd ? OUTPUT_PROD : OUTPUT_DEV,

  module: {
    rules: [
      isProd
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
      isProd
        ? {
          test: /\.(sa|sc|c)ss$/,
          use: [
            {
              loader: MiniCssExtractPlugin.loader
            },
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
        use: [
          {
            loader: 'url-loader',
            options: {
              limit: 8192,
              name: '[path][name].[ext]'
            },
          },
        ]
      }
    ]
  },

  plugins: PLUGINS,

  stats: {
    colors: true
  }
}

module.exports = cfg
