import { defineConfig } from 'vite'
import { fileURLToPath } from 'node:url'
import consumer from './vite.config.js'

// The same consumer plugin/runtime resolution, with no Phoenix or database.
export default defineConfig({
  ...consumer,
  root: fileURLToPath(new URL('./', import.meta.url)),
  plugins: [...consumer.plugins, { name: 'editor-fixture', resolveId(id) { if (id === '/tiptap-fixture.js') return fileURLToPath(new URL('../../../test/javascript/tiptap/fixture.js', import.meta.url)) } }],
  optimizeDeps: { include: ['svelte'] },
  resolve: { dedupe: ['svelte'] },
  server: { host: '127.0.0.1', port: Number(process.env.BRANDO_TIPTAP_TEST_PORT || 4488), strictPort: true, fs: { allow: [fileURLToPath(new URL('../../../', import.meta.url))] } },
})
