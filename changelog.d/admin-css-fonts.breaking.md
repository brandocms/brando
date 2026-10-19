- The admin's `Main` and `Mono` font families are removed
  ([#3213](https://github.com/brandocms/brando/pull/3213)).
  Admin CSS that names them writes `var(--brando-font-sans)` or `var(--brando-font-mono)`.
  An application that redefined `Main` in `@font-face` sets `theme.typography.families.main` in its
  `europa.json5` and loads the font itself.
  `assets/backend/public/fonts/Main-*.woff2` and `Mono.woff2` can be deleted unless the
  application's own CSS loads them.

- The admin's fonts 404 under the Vite dev server unless its config sets `server.origin`
  ([#3213](https://github.com/brandocms/brando/pull/3213)).
  Add ``origin: `http://${host}:${port}` `` to `server` in `assets/backend/vite.config.js`, next to
  `host` and `port`.
