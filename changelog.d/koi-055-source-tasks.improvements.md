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
  (requests of ~155 ms instead of ~35 ms). A literal list naming anything
  besides the application is removed, leaving Phoenix's default, and listed
  with file and line.

- **`mix brando.migrate55` replaces the old installer's `DashboardLive`.** The
  installer before 0.55 wrote one that renders only a header. A
  `DashboardLive` exactly like it gets the current template, which renders
  Brando's dashboard; one that renders `Content.header` but differs is
  listed.
