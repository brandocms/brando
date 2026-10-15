- **`@brandocms/brandojs` is ready to publish to npm.** Its `package.json`
  has a `files` allowlist (`src`, `css`, `vite`, `europa.json5`), so the
  package ships what an application's Vite build imports and leaves out the
  standalone `vite.config.js`; it also gains a description, the MIT licence
  (with `LICENSE.md` in the package), repository, homepage and issue links,
  `publishConfig` (public, `beta` dist-tag), and `svelte` as a peer
  dependency, since its source imports it. Its README, previously the Svelte
  template's, says what the package is, that its version must match `brando`
  exactly, and how `assets/backend` uses it. `scripts/release-version check`
  also fails when `assets/LICENSE.md` differs from the root `LICENSE.md`.

- **`scripts/release-version` keeps Hex, npm and the release tag on one
  version.** `scripts/release-version check` (part of `mix check` and CI)
  fails unless `assets/package.json` has `mix.exs`'s version, its
  `publishConfig.tag` is `beta` for a prerelease and `latest` for a stable
  version, the generator's BrandoJS and Brando pins are that exact version or
  a local source, Phoenix and LiveView have the same exact versions in
  `mix.exs`, `e2e/mix.exs` and `assets/package.json`, and a release tag
  (`--tag`, or the pushed tag in GitHub Actions) is `v` + the version. A
  version must be SemVer 2.0 without build metadata, so `0.55.0-beta.01`,
  which Elixir and npm reject, fails. A pushed `v*` tag runs the check in the
  new `Release tag` workflow. `scripts/release-version bump VERSION` sets the
  version in all of them, writing nothing unless every edit succeeds.
  `RELEASE.md` describes the release with it: one version, npm then Hex,
  then the GitHub release.
