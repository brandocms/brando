- In development a site without `assets/frontend/js/critical.js` no longer requests `js/critical.js`
  from its Vite dev server, which answered 404 and showed the "Site assets failed to load" notice.
