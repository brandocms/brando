- **The admin's `Main` and `Mono` font families are gone.** Admin CSS that
  names them writes `var(--brando-font-sans)` or `var(--brando-font-mono)`
  instead. An application that gave the admin its own font by redefining
  `Main` in `@font-face` sets `theme.typography.families.main` in its
  `europa.json5` and loads that font itself. After upgrading,
  `assets/backend/public/fonts/Main-*.woff2` and `Mono.woff2` are unused
  and can be deleted, unless the application's own CSS loads them.

- **Set `server.origin` in the admin's Vite config.** The admin's fonts are
  now bundled assets, and in development Vite writes their URLs relative to
  its own server, while the admin page comes from Phoenix. Add
  ``origin: `http://${host}:${port}` `` to `server` in
  `assets/backend/vite.config.js`, next to `host` and `port`, as the
  installer's template now does; without it the fonts 404 under `yarn dev`
  and the admin falls back to system fonts.
