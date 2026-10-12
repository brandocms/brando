- **A missing admin build says so in development, instead of a blank page.**
  When the admin's Vite dev server cannot be reached (`hmr` on, `pnpm dev`
  not running in `assets/backend`), or `hmr: false` and there is no
  `priv/static/admin_manifest.json`, the admin shows a notice naming the
  server and what to run. It is rendered in `:dev` only.
