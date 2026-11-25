- A static site records when each environment's content last changed and when each build started, so it can tell whether the deployed build lacks changes made since (`Brando.SSG.ContentChanges`).
  Run `mix brando.gen.migrations` for `brando_250`, then `mix brando.migrate` before the new release starts.
  In a release, run `bin/my_app eval "MyApp.ReleaseTasks.migrate()"` from the new release.
