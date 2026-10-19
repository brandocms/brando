- A has_many multi select without `relation:` fails to compile, and `mix brando.migrate54` adds the
  option ([#3169](https://github.com/brandocms/brando/pull/3169)).

- An `:entries` input's `sources:` options that identifiers cannot apply fail to compile, and `mix
  brando.migrate54` drops them ([#3169](https://github.com/brandocms/brando/pull/3169)).

- `mix brando.migrate54` points fragment map reads of `.html` at `rendered_blocks`, and lists the
  ones it cannot rewrite ([#3169](https://github.com/brandocms/brando/pull/3169)).

- `mix brando.migrate55` lists reads of `:entries` relations, which hold join rows since 0.54
  ([#3169](https://github.com/brandocms/brando/pull/3169)).
  Preload `related_entries: :identifier` and read `& &1.identifier.entry_id`.

- `mix brando.migrate55` writes `identifier false` on embedded Blueprints and rewrites
  `default_srcset:` in image configs to `srcset: %{default: […]}`
  ([#3169](https://github.com/brandocms/brando/pull/3169)).
