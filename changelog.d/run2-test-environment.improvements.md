- `mix brando.migrate55` and `mix brando.doctor` warn when `mix test` would use the development
  database because `config/runtime.exs` reads the Repo's `url:` outside a guard that excludes
  `:test` ([#3167](https://github.com/brandocms/brando/pull/3167)).
  Move that line inside an `if config_env() …` guard that excludes `:test`.
