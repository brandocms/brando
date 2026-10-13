- **`mix brando.migrate54` writes the Brando settings `mix brando.migrate55`
  and `mix brando.doctor` ask for.** Each change to the application's
  configuration recompiles Brando. Besides `repo_module`, the task now points
  Brando at the application's mailer (creating `MyApp.Mailer` when it has
  none) and writes a placeholder sender, so the settings change once; replace
  the placeholder before you first compile. The mailer step writes the
  placeholder whenever no `config/*.exs` file sets a sender, inside an
  `if config_env() == :prod` block included.

- **A placeholder sender counts as no sender outside development.** Brando
  sends nothing from an address on a domain reserved for examples
  (`example.com`, `example.org`, `example.net`, `*.example`) outside `:dev`
  and `:test`: it logs and returns `{:error, :no_sender}`, as without a
  sender, and `mix brando.doctor` reports it as an error instead of a
  warning.

- **`mix brando.migrate55` removes dependencies from the endpoint's
  `reloadable_apps`.** With `reloadable_apps: [:my_app, :brando]`, the code
  reloader checks Brando's sources on every development request, and on
  Elixir 1.19 and later each check rebuilds the application's protocols
  (requests of ~155 ms instead of ~35 ms). `:brando` and the Hex and git
  dependencies leave the list; the application and path dependencies stay.
  A list left with only the application is removed, leaving Phoenix's
  default. Each change is listed with file and line.

- **`mix brando.migrate55` replaces the old installer's `DashboardLive`.** The
  installer before 0.55 wrote one that renders only a header. A
  `DashboardLive` exactly like it gets the current template, which renders
  Brando's dashboard; one that renders `Content.header` but differs is
  listed.

- **`mix brando.migrate55` removes a redundant `use Phoenix.Component`.** A
  module that says `use BrandoWeb, :html` (or a kind of the application's
  web module that uses Phoenix.Component) and then `use Phoenix.Component`
  makes Elixir 1.20 warn about a redundant `__phoenix_component_verify__`
  clause, which fails `--warnings-as-errors`. The second `use` goes, and
  each is listed with file and line.

- **`get_entries_from_identifiers/2` with a list of preloads is rewritten and
  reported.** `mix brando.migrate55` writes
  `get_entries_from_identifiers(ids, [:cover])` as
  `get_entries_from_identifiers(ids, %{preload: [:cover]})` and lists a call
  whose preloads it cannot read; `mix brando.doctor`'s Deprecations check
  reports the list form, which warns with a stacktrace on every call.
