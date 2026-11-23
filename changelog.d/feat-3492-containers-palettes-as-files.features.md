- Palettes and containers can be definition files (`kind :palette`, `kind :container`): `mix brando.modules export` writes them beside the modules, and the import, the admin's ZIP, the development watcher and a release's Release changes apply them, palettes first.
  Run `mix brando.gen.migrations` for `brando_245`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
