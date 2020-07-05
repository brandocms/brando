/* eslint-disable import/no-extraneous-dependencies */

import babel from '@rollup/plugin-babel'
import commonjs from '@rollup/plugin-commonjs'
import copy from 'rollup-plugin-copy'
import postcss from 'rollup-plugin-postcss'
import replace from '@rollup/plugin-replace'
import resolve from '@rollup/plugin-node-resolve'
import sizes from 'rollup-plugin-sizes'
import { terser } from 'rollup-plugin-terser'
import pkg from './package.json'

const prod = process.env.NODE_ENV === 'production'

function plugins({ type } = {}) {
  const browsers = type === 'nomodule' ? ['ie 11'] : pkg.browserslist.modernBrowsers

  const pluginList = [
    resolve(),
    commonjs(),
    babel({
      babelHelpers: 'bundled',
      exclude: ['node_modules/**', '!node_modules/@univers-agency/jupiter', '!node_modules/@univers-agency/panama'],
      presets: [['@babel/preset-env', {
        targets: { browsers },
        useBuiltIns: 'usage',
        corejs: 3
      }]]
    }),
    replace({ 'process.env.NODE_ENV': JSON.stringify('production') }),
    postcss({
      extract: 'css/app.css',
      minimize: prod,
      sourceMap: true
    }),
    copy({
      targets: [
        { src: 'static/**/*', dest: pkg.publicDir }
      ],
      copyOnce: true
    })
  ]
  // Only add minification in production
  if (prod) {
    pluginList.push(terser({
      module: type !== 'nomodule',
      mangle: true,
      safari10: true,
      output: {
        comments: false
      },
      compress: {
        global_defs: {
          module: false
        }
      }
    }))
    pluginList.push(sizes())
  }

  return pluginList
}

// Module config for <script type="module">
const moduleConfig = {
  input: { module: 'js/polyfills.modern.js' },
  output: {
    dir: pkg.publicDir,
    format: 'esm',
    entryFileNames: 'js/app.js',
    sourcemap: true,
    banner: '/* hepp */'
  },
  plugins: plugins({ type: 'module' }),
  watch: { clearScreen: false }
}

// Legacy config for <script nomodule>
const nomoduleConfig = {
  input: { nomodule: 'js/polyfills.legacy.js' },
  output: {
    dir: pkg.publicDir,
    format: 'iife',
    entryFileNames: 'js/app.legacy.js'
  },
  plugins: plugins({ type: 'nomodule' }),
  inlineDynamicImports: true
}

const configs = prod ? [moduleConfig, nomoduleConfig] : [moduleConfig]

export default configs
