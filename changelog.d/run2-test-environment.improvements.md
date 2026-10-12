- **`mix brando.migrate55` and `mix brando.doctor` warn when `mix test` would
  use the development database.** A `config/runtime.exs` that reads the Repo's
  `url:` from an environment variable outside an `if config_env() …` guard
  that excludes `:test` overrides `config/test.exs`, so `mix test`, whose
  alias runs `ecto.migrate`, migrates whatever database the shell names.
  `mix brando.migrate55` names the line and the guard to add, and also warns
  when `test_paths` in `mix.exs` names a directory that does not exist. The
  doctor's new Test database check, in development, reads the test
  configuration and warns when it resolves to the database in use. New
  installations read `BRANDO_DB_URL` only outside `:test` and `:e2e`.
