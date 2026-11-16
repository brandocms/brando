- `mix brando.repair.legacy_media` puts back media that an older `brando_133` lost in the blocks
  conversion ([#3170](https://github.com/brandocms/brando/pull/3170)).
  Run it while the Villain columns are still there (`--dry-run` lists what it would do), then run
  `mix brando.entries.resave`. It has no release form: run it from a checkout against the
  server's database; the resave runs in a release as `bin/my_app rpc "MyApp.ReleaseTasks.resave_entries()"`.

- `mix brando.doctor` lists module code that still reads entries through `.data.vars` or
  `.data.refs` ([#3170](https://github.com/brandocms/brando/pull/3170)).
