- `mix brando.migrate55` sets `persist_identifier false` on Blueprints that no admin route,
  datasource, relation or `absolute_url` can open or select, so `mix brando.identifiers.sync` then
  deletes their identifiers; other Blueprints without an editor are listed with the reason
  ([#3167](https://github.com/brandocms/brando/pull/3167)).
