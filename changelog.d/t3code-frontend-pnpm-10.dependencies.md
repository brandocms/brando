- **The generated frontend builds with pnpm 10 and Jupiter `5.0.0-beta.19`**.
  The frontend template's `packageManager` moves from pnpm 9.14.3 to 10.32.1,
  the version the backend already uses, and its lockfile is regenerated: it
  had fallen behind `package.json` at `@brandocms/europacss` `1.0.0-beta.3`.
  The Dockerfile's `assets_frontend` stage installs `pnpm@10.32.1` instead of
  activating `pnpm@latest`. pnpm 10 skips dependency install scripts unless a
  package is approved; the template lists `core-js` (a donation banner) as
  ignored. In an existing application, set the same `packageManager`, run
  `pnpm install` in `assets/frontend` and commit the lockfile.

- **The E2E frontend moves from yarn 1 to pnpm 10.32.1**, like every other
  package in the repository. Its lockfile was imported from `yarn.lock`, so
  resolved versions are unchanged apart from Jupiter `5.0.0-beta.19`. Its
  `postcss.config.js` requires `autoprefixer`, which is now declared rather
  than reached through yarn's hoisting, and `postcss-functions` is overridden
  to the same HTTPS tarball yarn resolved, so pnpm does not fetch it over SSH.
