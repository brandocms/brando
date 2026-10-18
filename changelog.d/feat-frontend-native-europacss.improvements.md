- **A new site's frontend builds with the native EuropaCSS compiler.**
  `mix brando.install` writes `assets/frontend` with
  `@brandocms/vite-plugin-europacss` and `@brandocms/europacss-cli`, as the
  admin already has, and a `europa.json5` with the site's tokens in place of
  `europa.config.cjs`, `postcss.config.cjs` and the legacy
  `@brandocms/europacss` 1.0.0-beta.16. The build no longer warns that a
  PostCSS plugin did not pass `from`, and the Vite plugin updates the CSS when
  `europa.json5` changes. The generated pages look as before, except that the
  terminal block on the start page gets the 4px corner radius its stylesheet
  asked for. Existing sites keep their frontend; "Site frontend" in the 0.55
  migration guide describes the optional switch.
