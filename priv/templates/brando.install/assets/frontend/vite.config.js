import { defineConfig } from 'vite'
import legacy from '@vitejs/plugin-legacy'

// https://vitejs.dev/config/
export default defineConfig({
  build: {
    manifest: true,
    emptyOutDir: false,
    target: "es2015",
    outDir: "../../priv/static", // <- Phoenix expects our files here
    sourcemap: true, // we want to debug our code in production
    rollupOptions: {
      input: {
        main: "js/index.js",
        critical: "js/critical.js"
      }
    },
    terserOptions: {
      mangle: true,
      safari10: true,
      output: {
        comments: false
      },
      compress: {
        pure_funcs: ['console.info', 'console.debug', 'console.warn'],
        global_defs: {
          module: false
        }
      }
    }
  },

  plugins: [
    legacy({
      // The browsers that must be supported by your legacy bundle.
      // https://babeljs.io/docs/en/babel-preset-env#targets
      targets: [
        '> 0.5%',
        'last 2 versions',
        'Firefox ESR',
        'not dead',
      ],
      // Define which polyfills your legacy bundle needs. They will be loaded
      // from the Polyfill.io server. See the "Polyfills" section for more info.
      additionalLegacyPolyfills: [
        'intersection-observer',
        'custom-event-polyfill',
        'element-polyfill',
        'picturefill'
      ],
      corejs: true
    })
  ]
})