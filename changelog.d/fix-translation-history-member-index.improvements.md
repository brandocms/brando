- Saving a source entry whose synchronized translations still have text to translate no longer reads every translation's version history: `brando_235` indexes `translation_pending_versions` by translation.
  Run `mix brando.gen.migrations` for `brando_235`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
