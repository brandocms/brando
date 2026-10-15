- **`mix brando.doctor` checks the admin's CSS compiler.** The Admin CSS
  compiler check warns while `assets/backend` is not on the native EuropaCSS
  packages at the versions Brando's backend template pins: the legacy
  `@brandocms/europacss`, a Yalc copy or path of the Vite plugin, another
  version, or `node_modules` behind `package.json`. Its fix is
  `mix brando.gen.backend --upgrade` and `mix brando.assets.setup
  --backend-only`, or `pnpm install`. `mix brando.migrate55` adds a notice
  saying the same when it finds such a backend.
