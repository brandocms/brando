- **The admin's CSS builds with native EuropaCSS** (#3187). The Rust compiler
  runs through `@brandocms/vite-plugin-europacss` in the application's Vite
  build, replacing the `@brandocms/europacss` PostCSS plugin and
  `autoprefixer`. `assets/backend/europa.json5` extends BrandoJS's preset
  (`europa.json5`, whose `nesting: 'expanded'` and `responsiveOrder:
  'generated-last'` keep 0.13's selectors and media order) in place of
  `europa.config.cjs`; `mix brando.gen.backend --upgrade` creates it, updates the packages and
  `vite.config.js`, and removes unchanged template copies of
  `postcss.config.cjs` and `europa.config.cjs`, keeping an application's own
  with a notice. The admin's styles are in the cascade layers `reset, vendor,
  brando, app`: application CSS in `@layer app` outranks Brando's rules
  without matching their selectors, and an `!important` in Brando's layer
  outranks one in `app`. `@row` and `@container;` are gone and `@keyframes`
  cannot be nested in a rule; the upgrade task lists the `@row`s it finds.
  `theme.colors` is the admin's supported palette: `tokens.css` sets the
  matching roles and the `--brando-color-*` names from it, so an application's
  `europa.json5` recolours the admin. Until the native packages are
  published, a build needs the `europa` executable and the Vite plugin from a
  EuropaCSS checkout. See "Native EuropaCSS" in
  [Migrating from 0.53](guides/migrating_from_053.md#native-europacss).
