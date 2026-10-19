- `mix brando.repair.legacy_media` puts back media that an older `brando_133` lost in the blocks
  conversion ([#3170](https://github.com/brandocms/brando/pull/3170)).
  Run it while the Villain columns are still there (`--dry-run` lists what it would do), then run
  `mix brando.entries.resave`.

- `mix brando.doctor` lists module code that still reads entries through `.data.vars` or
  `.data.refs` ([#3170](https://github.com/brandocms/brando/pull/3170)).
