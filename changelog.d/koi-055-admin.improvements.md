- In development, a missing admin build shows a notice naming what to run
  ([#3173](https://github.com/brandocms/brando/pull/3173)).

- The admin build no longer warns that a PostCSS plugin did not pass the `from` option
  ([#3173](https://github.com/brandocms/brando/pull/3173)).
  `mix brando.gen.backend --upgrade` updates an unchanged earlier template's `postcss.config.cjs`.

- The admin no longer bundles core-js 2, so pnpm 10 stops printing "Ignored build scripts: core-js"
  ([#3173](https://github.com/brandocms/brando/pull/3173)).
