import yalcAutoUpdate from '@brandocms/brandojs/vite/yalcAutoUpdate.mjs'
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
    watch: {
      // brandojs is installed from .yalc, so `yalc update` writes it straight
      // into node_modules -- which Vite's watcher ignores by default. Without
      // this the transform cache is never invalidated and the copy from before
      // the update keeps being served, even across a hard reload. The `!`
      // re-includes just this package.
      ignored: ['!**/node_modules/@brandocms/brandojs/**'],
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
    rolldownOptions: {
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

  // `yalc publish` in brando/assets only writes to the yalc store. This pulls
  // it from there into this project as it lands, so the admin never runs new
  // templates against the JS from a previous publish.
  plugins: [svelte(), yalcAutoUpdate()],
})
