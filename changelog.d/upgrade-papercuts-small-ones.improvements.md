- `mix brando.upgrade.database` no longer stops after copying Brando's migrations: the copies are Brando's templates, so it goes on to `mix brando.migrations.check`, which stops the run if one differs, and `mix brando.migrate` still asks before running them.

- `mix brando.migrate55` lists the `list_*` calls without an `order:` only until the application has copies of Brando's 0.55 migrations, so rerunning it on a 0.55 development build no longer repeats the warning.
