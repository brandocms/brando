- Live previews are sandboxed, so they connect to a socket of their own and load the site's module scripts, fonts and `fetch` calls cross-origin; the site's `localStorage`, `sessionStorage` and `document.cookie` keep values in memory only there.
  `mix brando.migrate55` makes both endpoint changes; check it did:
  1. Mount the preview socket next to `socket "/admin/socket"`: `socket "/__livepreview/socket", BrandoAdmin.LivePreviewSocket, websocket: [check_origin: false], longpoll: false`. Without it the preview shows no live updates and says so.
  2. Keep `plug Brando.Plug.SiteAssets` right before `plug Plug.Static`; it sends the site's static files with `Access-Control-Allow-Origin: *`.
  3. Purge a CDN's cached static files once after deploying, so it stops serving copies without that header.
  4. A preview script that fetches from the site's own routes needs `Access-Control-Allow-Origin` on them; with the Vite dev server, allow any origin in `server.cors`.
