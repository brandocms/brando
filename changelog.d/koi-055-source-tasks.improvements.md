- `mix brando.migrate54` writes the mailer and sender settings that `mix brando.migrate55` and the
  doctor ask for ([#3171](https://github.com/brandocms/brando/pull/3171)).
  Replace the placeholder sender before you first compile.

- Brando sends nothing from a placeholder sender on an example domain (`example.com` and the like)
  outside `:dev` and `:test`, and the doctor reports it as an error
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` removes `:brando` and the other Hex and git dependencies from the
  endpoint's `reloadable_apps` ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` replaces the old installer's header-only `DashboardLive` with the current
  one ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` removes a redundant `use Phoenix.Component` that Elixir 1.20 warns about
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` rewrites `get_entries_from_identifiers/2` with a list of preloads to
  `%{preload: […]}`, and the doctor reports the list form
  ([#3171](https://github.com/brandocms/brando/pull/3171)).
