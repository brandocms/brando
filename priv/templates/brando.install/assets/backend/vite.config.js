
import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    port: 3333
  },
  build: {
    manifest: true,
    emptyOutDir: false,
    target: "modules",
    outDir: "../../priv/static", // <- Phoenix expects our files here
    sourcemap: true, // we want to debug our code in production
    rollupOptions: {
      input: {
        admin: "src/main.js",
        auth: "src/auth.js"
      },
      output: {
        entryFileNames: `assets/admin/[name].js`,
        chunkFileNames: `assets/admin/[name].js`,
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