- **A new site's frontend builds with the native EuropaCSS compiler** (#3235).
  `mix brando.install` writes `assets/frontend` with
  `@brandocms/vite-plugin-europacss` and `@brandocms/europacss-cli`, as the
  admin already has, and a `europa.json5` with the site's tokens in place of
  `europa.config.cjs`, `postcss.config.cjs` and the legacy
  `@brandocms/europacss` 1.0.0-beta.16. The build no longer warns that a
  PostCSS plugin did not pass `from`, and the Vite plugin updates the CSS when
  `europa.json5` changes. Declarations the legacy build silently dropped now
  apply as written: the terminal block gets its 4px corner radius, the mono
  labels, ledger figures, commands and body text get the line heights their
  rules name, and the hero buttons, closing row, footer lists and ledger get
  their mobile spacing. The cards and tips space their rows with `row-gap` and
  `column-gap` instead of margins. Existing sites keep their frontend;
  "Site frontend" in the 0.55 migration guide describes the optional switch.
