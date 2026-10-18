import { defineConfig } from 'vite'
import legacy from '@vitejs/plugin-legacy'
import europa from '@brandocms/vite-plugin-europacss'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    port: 3000,
  },
  css: {
    devSourcemap: true,
    // No PostCSS config: EuropaCSS and Vite's Lightning CSS pass do its work.
    postcss: { plugins: [] },
  },
  build: {
    manifest: 'manifest.json',
    emptyOutDir: false,
    outDir: '../../priv/static', // <- Phoenix expects our files here
    // Maps are written without a sourceMappingURL comment, so browsers never
    // ask for them. `mix brando.digest` deletes them before release; upload
    // them to Sentry first if you want readable stack traces.
    sourcemap: 'hidden',
    rolldownOptions: {
      input: {
        main: 'js/index.js',
        critical: 'js/critical.js',
      },
    },
    terserOptions: {
      mangle: true,
      safari10: true,
      format: {
        comments: false,
      },
      compress: {
        pure_funcs: ['console.info', 'console.debug', 'console.warn'],
        global_defs: {
          module: false,
        },
      },
    },
  },

  // EuropaCSS compiles the site's stylesheets with the `europa` executable,
  // using europa.json5. It watches europa.json5 and hot-updates the CSS when
  // it changes.
  plugins: [
    europa({
      config: './europa.json5',
      targets: ['defaults'],
    }),
    legacy({
      // The browsers that must be supported by your legacy bundle.
      // https://babeljs.io/docs/en/babel-preset-env#targets
      targets: ['> 0.5%', 'last 2 versions', 'Firefox ESR', 'not dead'],
      // Define which polyfills your legacy bundle needs. They will be loaded
      // from the Polyfill.io server. See the "Polyfills" section for more info.
      additionalLegacyPolyfills: [
        'intersection-observer',
        'custom-event-polyfill',
        'element-polyfill',
        'picturefill',
      ],
      corejs: true,
    }),
  ],
})
