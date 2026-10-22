- The admin's CSS builds with native EuropaCSS through `@brandocms/vite-plugin-europacss`, replacing
  the `@brandocms/europacss` PostCSS plugin and `autoprefixer`
  ([#3189](https://github.com/brandocms/brando/pull/3189)).
  Run `mix brando.gen.backend --upgrade`: it creates `assets/backend/europa.json5`, updates the
  packages and `vite.config.js`, and removes unchanged `postcss.config.cjs` and `europa.config.cjs`.
  Remove `@row` and `@container;` from the admin's CSS (the upgrade lists the `@row`s) and move
  nested `@keyframes` out of their rules.
  Put application CSS in `@layer app` to override Brando's rules, and recolour the admin through
  `theme.colors` in `europa.json5`.
  The CLI is `pnpm exec europa`. See [Native
  EuropaCSS](guides/migrating_from_053.md#native-europacss).
