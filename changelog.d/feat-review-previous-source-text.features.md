- A synchronized translation's review item keeps the source's text from before the change: `translation_work` gives it as `source_previous`, Translate with AI asks for the smallest change that follows it, and the `translate` review card shows the source and the translation before and now.
  Run `mix brando.gen.migrations` for `brando_239`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
