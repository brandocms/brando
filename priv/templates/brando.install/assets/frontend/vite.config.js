import { defineConfig } from 'vite'
import legacy from '@vitejs/plugin-legacy'
import eslint from 'vite-plugin-eslint'
import europa from '@brandocms/vite-plugin-europacss'

// Export these in the same environment as Phoenix; Brando.HTML reads them too.
const host = process.env.BRANDO_VITE_FRONTEND_HOST ?? 'localhost'
const port = Number(process.env.BRANDO_VITE_FRONTEND_PORT ?? 3000)

// https://vitejs.dev/config/
export default defineConfig(({ command }) => ({
  base: './',
  server: {
    host,
    port,
    // A taken port is an error, not a move to the next free one: Brando.HTML
    // loads the site from this port, and another site's server may hold it.
    strictPort: true,
    cors: 'localhost',
    hmr: {
      port,
    },
  },
  css: {
    devSourcemap: true,
    // No PostCSS config: EuropaCSS and Vite's Lightning CSS pass do its work.
    postcss: { plugins: [] },
  },
  build: {
    manifest: 'manifest.json',
    cssMinify: 'lightningcss',
    minify: 'terser',
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
      format: { comments: false },
      compress: {
        pure_funcs: ['console.info', 'console.debug', 'console.warn'],
      },
    },
  },

  // EuropaCSS compiles the site's stylesheets with the `europa` executable,
  // using europa.json5, under one browser policy for Europa's transforms and
  // Vite's CSS minifier. It watches europa.json5 and hot-updates the CSS when
  // it changes.
  plugins: [
    europa({
      config: './europa.json5',
      targets: ['defaults'],
    }),
    eslint({
      failOnError: command === 'build',
      failOnWarning: false,
      cache: false,
    }),

    legacy({}),
  ],
}))
