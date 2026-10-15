# @brandocms/brandojs

BrandoJS is the admin frontend of [Brando CMS](https://github.com/brandocms/brando):
the LiveView hooks, Svelte components, rich-text editor and CSS of the Brando admin.

It is a source package. It ships JavaScript, Svelte and CSS source and the
admin's EuropaCSS configuration, not a built bundle; the application's own Vite
build compiles it.

## Version

Use the BrandoJS version that matches the application's `brando` Hex package
exactly: `brando` 0.55.0-beta.0 goes with `@brandocms/brandojs` 0.55.0-beta.0.
Both are released together from the same commit, and an admin whose JavaScript
comes from another release does not match its server. `mix brando.doctor`
reports a mismatch.

Prereleases are published under the `beta` dist-tag, stable releases under
`latest`.

## Installation

A Brando application builds its admin in `assets/backend`. Add the package
there, pinned to the exact version of `brando`, for example:

```json
{
  "dependencies": {
    "@brandocms/brandojs": "0.55.0-beta.0"
  }
}
```

`assets/backend` uses it in three places:

- `src/main.js` imports the admin's CSS and builds the application:
  `import '@brandocms/brandojs/css/app.css'` and
  `import { buildApplication } from '@brandocms/brandojs'`.
- `europa.json5` extends `./node_modules/@brandocms/brandojs/europa.json5`.
- `vite.config.js` imports `@brandocms/brandojs/vite/yalcAutoUpdate.mjs`, a
  development helper for a BrandoJS linked from a local checkout. It does
  nothing when the application has no `yalc.lock`.

Brando's installer generates these files. Upgrade BrandoJS together with
`brando`, then rebuild the admin assets.

## Documentation

The Brando guides cover installation, upgrades and the admin:
[guides/](https://github.com/brandocms/brando/tree/main/guides), starting with
[Installation and generators](https://github.com/brandocms/brando/blob/main/guides/generators.md).

## License

MIT
