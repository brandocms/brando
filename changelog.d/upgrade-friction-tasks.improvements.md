- `mix brando.doctor` reports Blueprints whose admin form route (`admin_<singular>_form_path`) is
  missing ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `mix brando.migrate54` and `mix brando.migrate55` list the files they write when run with `--yes`
  ([#3161](https://github.com/brandocms/brando/pull/3161)).

- `mix brando.migrate55` adds `Brando.Plug.Markdown` and `Brando.Plug.IndexNow` to the endpoint,
  before the router ([#3161](https://github.com/brandocms/brando/pull/3161)).
