- `mix brando.migrate54` preloads page vars read on `assigns[:page]` or `assigns.page`
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate54` merges a Create/Update form pair whose `<:header>` holds plain text
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate54` scopes adjacent flat admin routes that share a route helper
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate54` converts more legacy listing templates
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- A list and a selection datasource may share a name again
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate54` keeps `import Ecto.Query` in a Blueprint whose functions use its macros
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate54` writes a captured mutator in meta and datasource functions as a plain call
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` splits a Plural-Forms rule that an older Poedit ran into the next header
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` gives join schemas `persist_identifier false` when no `:entries` input's
  `sources:` names them ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` copies Blueprint translations only into the Blueprint's Gettext backend
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- The assistant lists a `:single` datasource's options again
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.doctor` checks the sender each site sends from
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- `mix brando.migrate55` reads `Config.config_env()` in `runtime.exs`
  ([#3171](https://github.com/brandocms/brando/pull/3171)).

- A `:single` datasource block renders its chosen entry
  ([#3171](https://github.com/brandocms/brando/pull/3171)).
