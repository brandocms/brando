- Legacy pictures and gallery images without an image row survive the blocks conversion
  ([#3170](https://github.com/brandocms/brando/pull/3170)).
  Sites that ran the old `brando_133` repair theirs with `mix brando.repair.legacy_media` before
  dropping the Villain columns.

- `mix brando.check.legacy_conversion` reports media refs that lost their media
  ([#3170](https://github.com/brandocms/brando/pull/3170)).

- Multi module code that reads its entries' vars the 0.53 way (`link.data.vars.url`) renders again
  ([#3170](https://github.com/brandocms/brando/pull/3170)).
  Run `mix brando.gen.migrations` for `brando_219`, then `mix brando.entries.resave`.
