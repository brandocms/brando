var path = require('path')
var utils = require('./utils')
var config = require('../config')
var vueLoaderConfig = require('./vue-loader.conf')

function resolve (dir) {
  return path.join(__dirname, '..', dir)
}

module.exports = {
  entry: {
    admin: [
      './styles/app.scss',
      './src/main.js'
    ]
  },
  output: {
    path: config.build.assetsRoot,
    filename: 'js/[name].js',
    publicPath: process.env.NODE_ENV === 'production'
      ? config.build.assetsPublicPath
      : config.dev.assetsPublicPath
  },
  resolve: {
    symlinks: false,
    extensions: ['.js', '.vue', '.json'],
    modules: [
      resolve('src'),
      resolve('node_modules')
    ],
    alias: {
      'vue$': 'vue/dist/vue.esm.js',
      '@': resolve('src')
    }
  },
  module: {
    rules: [
      {
        test: /\.vue$/,
        loader: 'vue-loader',
        options: vueLoaderConfig
      },
      {
        test: /\.js$/,
        loader: 'babel-loader',
        query: {
          presets: ['env']
        },
        include: [
          resolve('src'),
          resolve('test'),
          resolve('node_modules/kurtz/lib')
        ]
      },
      {
        test: /\.(png|jpe?g|gif|svg)(\?.*)?$/,
        loader: 'url-loader',
        query: {
          limit: 10,
          name: utils.assetsPath('images/[name].[ext]')
        }
      },
      {
        test: /\.(graphql|gql)$/,
        include: [
          resolve('src'),
          resolve('node_modules/kurtz/lib')
        ],
        loader: 'graphql-tag/loader',
      },
      {
        test: /\.(woff2?|eot|ttf|otf)(\?.*)?$/,
        loader: 'url-loader',
        query: {
          limit: 10,
          name: utils.assetsPath('fonts/[name].[ext]')
        }
      }
    ]
  }
}
