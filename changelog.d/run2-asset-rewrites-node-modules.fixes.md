- **`mix brando.migrate54` and `mix brando.migrate55` leave installed packages
  alone.** The font-URL and `phoenix_live_view` pin rewrites read every file
  under `assets/`, `node_modules` included, and could rewrite an installed
  package's `package.json` or CSS. They now skip `node_modules` and Yalc's
  store.
