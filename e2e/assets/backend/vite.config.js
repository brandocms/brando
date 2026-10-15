import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'
import europa from '@brandocms/vite-plugin-europacss'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    port: 3333
  },
  resolve: {},
  css: {
    devSourcemap: true,
    // No PostCSS config: EuropaCSS and Vite's Lightning CSS pass do its work.
    postcss: { plugins: [] }
  },
  build: {
    manifest: 'admin_manifest.json',
    emptyOutDir: false,
    target: 'es2022',
    cssMinify: 'lightningcss',
    outDir: "../../priv/static", // <- Phoenix expects our files here
    // Maps are written without a sourceMappingURL comment, so browsers never
    // ask for them. `mix brando.digest` deletes them before release; upload
    // them to Sentry first if you want readable stack traces.
    sourcemap: 'hidden',
    rolldownOptions: {
      input: {
        admin: "src/main.js"
      },
      output: {
        entryFileNames: `assets/admin/admin-[hash].js`,
        chunkFileNames: `assets/admin/__[name]-[hash].js`,
        assetFileNames: `assets/admin/admin-[hash].[ext]`
      },
    },
    terserOptions: {
      mangle: true,
      safari10: true,
      format: {
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
    svelte({ configFile: false }),
    // Compiles the admin's stylesheets with the `europa` executable, using
    // europa.json5. One browser policy for Europa's transforms and Vite's CSS
    // minifier.
    europa({
      config: './europa.json5',
      targets: ['defaults']
    })
  ]
})
