- **When `Brando.Vite` cannot start Vite, the admin and the site no longer load
  another site's assets from its port.** With another site's Vite on port
  3333 (or 3000), the admin ran that site's admin JS and CSS and showed its
  Vite error overlay. The watcher now records the failure, and the page uses
  the last build in `priv/static` with a development notice saying that Vite
  did not start, why, and for a taken port which of `BRANDO_VITE_ADMIN_PORT`
  and `BRANDO_VITE_FRONTEND_PORT` to change; the notice can be closed. A
  `pnpm build` made while the server runs is used from the next page load, and
  a Vite that exits with an error after it started is treated the same way. A
  Vite run by hand with `pnpm dev` is loaded as before.
