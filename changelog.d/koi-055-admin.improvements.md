- **A missing admin build says so in development, instead of a blank page.**
  When the admin's Vite dev server cannot be reached (`hmr` on, `pnpm dev`
  not running in `assets/backend`), or `hmr: false` and there is no
  `priv/static/admin_manifest.json`, the admin shows a notice naming the
  server and what to run. It is rendered in `:dev` only.

- **The admin build no longer warns that "a PostCSS plugin did not pass the
  `from` option".** Europa writes rules and declarations without a source
  file, which Vite needs to resolve `url()`s and warns about. The backend
  template's `postcss.config.cjs` gives them the source of the file whose
  at-rule wrote them; `mix brando.gen.backend --upgrade` brings an unchanged
  earlier template's config up to date. The built CSS is the same.

- **The admin no longer pulls in core-js 2.** `idle-js`, used for the
  lobby's away state, bundled `@babel/polyfill` (core-js 2): pnpm 10 printed
  "Ignored build scripts: core-js" on every install of the backend, and the
  admin bundle carried 86 kB of polyfills. The away state is a few lines in
  `Presence` now, with the same 30 seconds and hidden-tab rules.
