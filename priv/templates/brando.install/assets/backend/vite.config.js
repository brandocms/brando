
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    port: 3333
  },
  optimizeDeps: {
    include: [
      'vex-js',
      'vex-dialog'
    ]
  },
  build: {
    manifest: false,
    emptyOutDir: false,
    target: "modules",
    outDir: "../../priv/static", // <- Phoenix expects our files here
    sourcemap: true, // we want to debug our code in production
    rollupOptions: {
      input: {
        admin: "src/main.js"
      },
      output: {
        manualChunks: () => 'everything.js',
        entryFileNames: `assets/admin/[name].js`,
        chunkFileNames: `assets/admin/__[name].js`,
        assetFileNames: `assets/admin/[name].[ext]`
      },
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
    svelte()
  ]
})