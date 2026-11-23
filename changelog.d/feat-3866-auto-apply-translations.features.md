- A connected AI tool's connection can be set to apply, without review, proposals that only create unpublished translations, under Configuration → Integrations → Connected AI tools.
  Run `mix brando.gen.migrations` for `brando_247`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
