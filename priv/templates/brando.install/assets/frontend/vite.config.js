import { defineConfig } from 'vite'
import legacy from '@vitejs/plugin-legacy'

function HMREuropa() {
  return {
    name: 'custom-hmr',
    enforce: 'post',
    // HMR
    handleHotUpdate({ file, server }) {
      if (file.endsWith('europa.config.cjs')) {
        console.log('europa.config.cjs updated. reloading...')

        server.ws.send({
          type: 'full-reload',
          path: '*',
        })
      }
    },
  }
}

// https://vitejs.dev/config/
export default defineConfig({
  base: './',
  server: {
    host: 'localhost',
    port: 3000,
    cors: 'localhost',
    hmr: {
      port: 3000,
    },
  },
  css: {
    devSourcemap: true,
  },
  build: {
    manifest: 'manifest.json',
    cssMinify: 'lightningcss',
    minify: 'terser',
    emptyOutDir: false,
    outDir: '../web/assets',
    sourcemap: true, // we want to debug our code in production
    rollupOptions: {
      input: {
        main: 'js/index.js',
        critical: 'js/critical.js',
      },
    },
    terserOptions: {
      mangle: true,
      output: { comments: false },
      compress: {
        pure_funcs: ['console.info', 'console.debug', 'console.warn'],
      },
    },
  },

  plugins: [HMREuropa(), legacy({})],
})
