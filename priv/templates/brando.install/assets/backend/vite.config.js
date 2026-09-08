import { defineConfig } from 'vite'
import { svelte } from '@sveltejs/vite-plugin-svelte'

// Export these in the same environment as Phoenix; Brando.HTML reads them too.
const host = process.env.BRANDO_VITE_ADMIN_HOST ?? 'localhost'
const port = Number(process.env.BRANDO_VITE_ADMIN_PORT ?? 3333)

// https://vitejs.dev/config/
export default defineConfig({
  server: {
    host,
    port,
    headers: {
      'Access-Control-Allow-Origin': '*',
    },
  },
  optimizeDeps: {
    include: ['vex-js', 'vex-dialog'],
  },
  build: {
    manifest: 'admin_manifest.json',
    emptyOutDir: false,
    target: 'es2022',
    outDir: '../../priv/static', // <- Phoenix expects our files here
    sourcemap: true, // we want to debug our code in production
    rollupOptions: {
      input: {
        admin: 'src/main.js',
      },
      output: {
        entryFileNames: `assets/admin/admin-[hash].js`,
        chunkFileNames: `assets/admin/__[name]-[hash].js`,
        assetFileNames: `assets/admin/admin-[hash].[ext]`,
      },
    },
    terserOptions: {
      mangle: true,
      safari10: true,
      output: {
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

  plugins: [svelte()],
})
