- **An application with Blueprints migrates an empty database again.** A new
  server's `ReleaseTasks.migrate()`, CI or a new test database stopped at
  `brando_53` with `relation "projects" does not exist`: Brando's data
  migrations `brando_53`, `brando_92`, `brando_93`, `brando_95`, `brando_96`,
  `brando_101` and `brando_102` find the application's tables through its
  current Blueprints, and on an empty database those tables are created by
  later migrations. They now skip a table or column that is not there yet
  (`Brando.Migration.Introspect`), and act as before where it is; `brando_80`
  uses the same check. `brando_53` no longer asks you to add your own schemas
  to a reject list. Copies installed earlier keep the old code: rewrite them
  with `mix brando.gen.migrations --refresh`.

- **A fresh install's `create_pages` migration no longer warns that
  `Brando.Villain.Migration.villain/0` is deprecated.** It adds the same `data`
  and `html` columns directly.
