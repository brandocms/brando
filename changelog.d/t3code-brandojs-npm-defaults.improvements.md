- A released Brando installs BrandoJS from npm, pinned to Brando's version; a `-dev` Brando still
  takes it from the Brando checkout through Yalc
  ([#3196](https://github.com/brandocms/brando/pull/3196)).
  `mix brando.assets.setup --local` (or `--source PATH`) switches the admin to a Yalc copy, and
  `--npm` switches it back.

- `mix brando.gen.backend --upgrade` moves an npm BrandoJS pin to Brando's version, keeps a Yalc
  copy or linked checkout, and updates the Dockerfile so it builds either
  ([#3196](https://github.com/brandocms/brando/pull/3196)).
  Once Brando is a release, run `mix brando.assets.setup --npm`.
